# SPDX-License-Identifier: AGPL-3.0
# Copyright (c) 2025, European Commission. Licensed under the AGPL-3.0
# Authors:
# Gianfranco Cedro
# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "jwt"

module Decidim
  module Keycloak
    # Service for managing Keycloak tokens: validation, refresh, revocation.
    #
    # @example Validate and refresh token
    #   TokenService.ensure_valid_token(user, cookies.to_h, cookies, request.host, self)
    #
    # @example Using options hash
    #   TokenService.ensure_valid_token(user, cookies_hash: cookies.to_h, cookies_obj: cookies)
    #
    class TokenService
      # Options hash for ensure_valid_token to reduce parameter count
      # @param user [Decidim::User] The user to validate token for
      # @param options [Hash] Options hash with :cookies_hash, :cookies_obj, :request_host, :controller
      def self.ensure_valid_token(user, options = {})
        new.ensure_valid_token(user, **options)
      end

      def self.revoke_tokens(access_token, refresh_token = nil)
        new.revoke_tokens(access_token, refresh_token)
      end

      def self.introspect_token(access_token)
        new.introspect_token(access_token)
      end

      # Exchange a token for a specific audience (public API)
      # @param subject_token [String] The token to exchange
      # @param audience [String] The target audience/client ID
      # @return [String, nil] The exchanged access token or nil on failure
      def self.exchange_token_for_audience(subject_token, audience)
        new.send(:exchange_token_for_audience, subject_token, audience)
      end

      # Ensure the user has a valid token, refreshing silently if expired.
      #
      # Flow:
      #   1. Local JWT expiry check (zero network) → return token if valid
      #   2. Token expired/missing → attempt silent refresh via Keycloak
      #   3. HTTP 200 → save new tokens, return new access_token
      #   4. HTTP 400/401 → return nil (definitive rejection → logout)
      #      Exception: if a successful refresh happened recently (concurrent request race),
      #      return :network_error to keep the session alive for this request.
      #   5. Network error → return :network_error (truthy → keep session, retry later)
      #
      # @param _user [Decidim::User] The user (unused but kept for API compatibility)
      # @param cookies_hash [Hash, nil] Hash of cookies
      # @param cookies_obj [ActionDispatch::Cookies, nil] Cookies object for writing
      # @param request_host [String, nil] Request host for cookie domain
      # @param controller [ActionController::Base, nil] Controller for callbacks
      # @return [String, Symbol, nil] token string or :network_error (truthy = keep session), nil = logout
      def ensure_valid_token(_user, cookies_hash: nil, cookies_obj: nil, request_host: nil, controller: nil)
        # Read from cookies first; fall back to session for large tokens that exceed
        # the browser's ~4096-byte cookie limit (access_token JWTs for admin users with
        # many roles can exceed this limit — browsers silently drop oversized cookies).
        access_token = reconstruct_token_from_cookies(cookies_hash, "access_token") ||
                       reconstruct_token_from_session(controller, :keycloak_access_token)
        # For refresh_token: session takes priority over cookie. Multiple concurrent SSO
        # login callbacks can overwrite the shared .ldttoolbox.app cookie, replacing one
        # session's refresh_token with another's. The session (Redis, per-session) holds
        # the correct token for THIS session; the cookie is only a fallback for the first
        # request before the session is populated.
        refresh_token = reconstruct_token_from_session(controller, :keycloak_refresh_token) ||
                        reconstruct_token_from_cookies(cookies_hash, "refresh_token")

        Rails.logger.debug do
          at = access_token.present? ? extract_jwt_expiration(access_token)&.iso8601 : "missing"
          rt = refresh_token.present? ? "present" : "missing"
          session_id = controller.respond_to?(:session) ? controller.session.id.to_s.first(8) : "n/a"
          at_cookie = reconstruct_token_from_cookies(cookies_hash, "access_token").present? ? "cookie" : "missing"
          at_session = reconstruct_token_from_session(controller, :keycloak_access_token).present? ? "session" : "missing"
          rt_session = reconstruct_token_from_session(controller, :keycloak_refresh_token).present? ? "session" : "missing"
          rt_cookie = reconstruct_token_from_cookies(cookies_hash, "refresh_token").present? ? "cookie" : "missing"
          "[Keycloak TokenService] ensure_valid_token: access_token=#{at} (src: cookie=#{at_cookie}, session=#{at_session}), refresh_token=#{rt} (src: session=#{rt_session}, cookie=#{rt_cookie}), session_id=#{session_id}"
        end

        # Step 1: Local JWT expiry check — no network call
        if access_token.present?
          result = validate_existing_token(access_token)
          return result if result
        end

        # Step 2: Token expired or missing → silent refresh
        handle_token_refresh(refresh_token, cookies_obj: cookies_obj, request_host: request_host, controller: controller)
      end

      def save_tokens_to_cookies(cookies_obj, tokens, request_host = nil)
        # CENTRALIZED: Uses Decidim::Keycloak::CookieManager
        Decidim::Keycloak::CookieManager.save_tokens(cookies_obj, tokens, request_host)
      end

      def revoke_tokens(access_token, refresh_token = nil)
        revoked = false

        revoked = revoke_token(access_token) || revoked if access_token.present?

        revoked = revoke_token(refresh_token) || revoked if refresh_token.present?

        revoked
      end

      def introspect_token(access_token)
        return false if access_token.blank?

        keycloak_site = ENV.fetch("OMNIAUTH_KEYCLOAK_SITE", nil)
        realm = ENV["OMNIAUTH_KEYCLOAK_REALM"] || "master"
        client_id = ENV.fetch("OMNIAUTH_KEYCLOAK_CLIENT_ID", nil)
        client_secret = ENV.fetch("OMNIAUTH_KEYCLOAK_CLIENT_SECRET", nil)

        introspect_endpoint = "#{keycloak_site.to_s.chomp('/')}/realms/#{realm}/protocol/openid-connect/token/introspect"

        begin
          uri = URI(introspect_endpoint)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"

          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/x-www-form-urlencoded"
          request.set_form_data(
            token: access_token,
            client_id: client_id,
            client_secret: client_secret
          )

          response = http.request(request)

          if response.code == "200"
            result = JSON.parse(response.body)
            active = result["active"]

            active == true
          else
            false
          end
        rescue StandardError => e
          false
        end
      end

      # How long (seconds) after a successful refresh during which a concurrent
      # 400/401 is treated as a token-rotation race rather than a genuine expiry.
      REFRESH_RACE_WINDOW_SECONDS = 30

      private

      # Exchange an incoming token (subject_token) for a token targeted at a specific audience/client
      # Returns the exchanged access_token string on success, or nil on failure.
      def exchange_token_for_audience(subject_token, audience)
        keycloak_site = ENV.fetch("OMNIAUTH_KEYCLOAK_SITE", nil)
        realm = ENV["OMNIAUTH_KEYCLOAK_REALM"] || "master"
        client_id = ENV.fetch("OMNIAUTH_KEYCLOAK_CLIENT_ID", nil)
        client_secret = ENV.fetch("OMNIAUTH_KEYCLOAK_CLIENT_SECRET", nil)

        token_endpoint = "#{keycloak_site.to_s.chomp("/")}/realms/#{realm}/protocol/openid-connect/token"

        # Try a couple of subject_token_type and client auth strategies if Keycloak rejects the first attempt
        subject_token_types = [
          "urn:ietf:params:oauth:token-type:access_token",
          "urn:ietf:params:oauth:token-type:id_token",
          "urn:ietf:params:oauth:token-type:jwt"
        ]

        client_auth_methods = [:post, :basic]

        client_auth_methods.each do |auth_method|
          subject_token_types.each do |sub_type|
            uri = URI(token_endpoint)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == "https"

            request = Net::HTTP::Post.new(uri)
            request["Content-Type"] = "application/x-www-form-urlencoded"

            form = {
              grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
              subject_token: subject_token,
              subject_token_type: sub_type,
              audience: audience,
              client_id: client_id
            }

            if auth_method == :post
              form[:client_secret] = client_secret
            else
              request.basic_auth(client_id, client_secret)
            end

            request.set_form_data(form)

            response = http.request(request)

            if response.code == "200"
              result = JSON.parse(response.body)
              return result["access_token"] if result["access_token"]
            end
          rescue StandardError => e
          end
        end

        nil
      end

      def reconstruct_token_from_cookies(cookies_hash, token_key)
        return nil unless cookies_hash

        # First, try direct access (normal single cookie)
        token = cookies_hash[token_key]
        return token if token.present?

        # Handle Rails cookie fragmentation for large tokens
        # Rails splits cookies > 4KB into fragments: token_0, token_1, ... + token.count
        fragment_count_key = "#{token_key}.count"
        fragment_count = cookies_hash[fragment_count_key].to_i

        if fragment_count > 0
          # Reassemble fragments in order
          fragments = []
          fragment_count.times do |i|
            fragment_key = "#{token_key}_#{i}"
            fragment = cookies_hash[fragment_key]
            fragments << fragment if fragment.present?
          end

          return fragments.join if fragments.length == fragment_count
        end

        nil
      end

      def refresh_access_token(refresh_token)
        keycloak_site = ENV.fetch("OMNIAUTH_KEYCLOAK_SITE", nil)
        realm = ENV["OMNIAUTH_KEYCLOAK_REALM"] || "master"
        client_id = ENV.fetch("OMNIAUTH_KEYCLOAK_CLIENT_ID", nil)
        client_secret = ENV.fetch("OMNIAUTH_KEYCLOAK_CLIENT_SECRET", nil)

        token_endpoint = "#{keycloak_site.to_s.chomp('/')}/realms/#{realm}/protocol/openid-connect/token"

        uri = URI(token_endpoint)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 5
        http.read_timeout = 5

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/x-www-form-urlencoded"
        request.set_form_data(
          grant_type: "refresh_token",
          refresh_token: refresh_token,
          client_id: client_id,
          client_secret: client_secret
        )

        response = http.request(request)

        case response.code.to_i
        when 200
          result = JSON.parse(response.body)
          {
            access_token: result["access_token"],
            refresh_token: result["refresh_token"] || refresh_token,
            id_token: result["id_token"],
            expires_in: result["expires_in"].to_i,
            refresh_token_expires_in: result["refresh_token_expires_in"]&.to_i
          }
        when 400, 401
          # Definitive rejection: refresh token expired/revoked → logout
          nil
        else
          # Unexpected server/proxy error → keep session, retry next request
          :network_error
        end
      rescue Net::TimeoutError, Net::OpenTimeout, Net::ReadTimeout,
             Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
        :network_error
      rescue StandardError => e
        :network_error
      end

      def revoke_token(token)
        return false if token.blank?

        keycloak_site = ENV.fetch("OMNIAUTH_KEYCLOAK_SITE", nil)
        realm = ENV["OMNIAUTH_KEYCLOAK_REALM"] || "master"
        client_id = ENV.fetch("OMNIAUTH_KEYCLOAK_CLIENT_ID", nil)
        client_secret = ENV.fetch("OMNIAUTH_KEYCLOAK_CLIENT_SECRET", nil)

        revoke_endpoint = "#{keycloak_site.to_s.chomp('/')}/realms/#{realm}/protocol/openid-connect/revoke"

        begin
          uri = URI(revoke_endpoint)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"

          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/x-www-form-urlencoded"
          request.set_form_data(
            token: token,
            client_id: client_id,
            client_secret: client_secret
          )

          response = http.request(request)

          if response.code == "200"
            true
          else
            false
          end
        rescue StandardError => e
          false
        end
      end

      # Local JWT expiry check — no network call.
      # Returns the token if still valid, nil if expired.
      # If expiry cannot be parsed (opaque token), assumes valid to avoid false logouts.
      def validate_existing_token(access_token)
        expires_at = extract_jwt_expiration(access_token)
        # Cannot parse expiry (e.g. opaque token) → assume valid
        return access_token unless expires_at

        # Token not yet expired locally → valid
        expires_at > Time.current ? access_token : nil
      end

      # Extract the exp claim from a JWT token (no signature verification needed).
      # Returns nil if the token is blank, opaque, or cannot be decoded.
      def extract_jwt_expiration(token)
        return nil if token.blank?

        payload = JWT.decode(token, nil, false).first
        exp = payload["exp"]
        exp ? Time.zone.at(exp) : nil
      rescue StandardError
        nil
      end

      def handle_token_refresh(refresh_token, cookies_obj: nil, request_host: nil, controller: nil)
        unless refresh_token && cookies_obj
          Rails.logger.warn "[Keycloak TokenService] handle_token_refresh: refresh_token=#{refresh_token.present? ? 'present' : 'nil'}, cookies_obj=#{cookies_obj.present? ? 'present' : 'nil'} — returning nil"
          return nil
        end

        new_tokens = refresh_access_token(refresh_token)

        case new_tokens
        when Hash
          # Successful refresh: persist new tokens, record timestamp, return new access token
          clear_cookies_if_controller(controller)
          save_tokens_to_cookies(cookies_obj, new_tokens, request_host)
          save_tokens_to_session(controller, new_tokens)
          record_refresh_timestamp(controller)
          new_tokens[:access_token]
        when :network_error
          # Transient failure: keep session alive, retry on next request
          :network_error
        else
          # nil: definitive rejection (400/401).
          #
          # Guard against token-rotation race condition: if two requests arrive
          # simultaneously when the access_token just expired, both read the same
          # stale refresh_token from request.cookies. The first request refreshes
          # successfully and Keycloak rotates the refresh_token; the second gets a
          # 400 (old token already used). Without this guard, the losing request
          # would immediately trigger perform_automatic_logout.
          #
          # Solution: if a successful refresh happened recently (within the race
          # window), treat the 400 as a transient error rather than a definitive
          # rejection. The browser will send the new tokens on the next request.
          if recent_successful_refresh?(controller)
            Rails.logger.warn "[Keycloak TokenService] 400/401 on refresh but a successful refresh occurred within " \
                              "#{REFRESH_RACE_WINDOW_SECONDS}s — likely a token-rotation race condition. " \
                              "Keeping session alive for this request."
            return :network_error
          end

          Rails.logger.warn "[Keycloak TokenService] 400/401 on refresh with no recent successful refresh — definitive rejection, forcing logout"
          clear_cookies_if_controller(controller)
          nil
        end
      end

      def clear_cookies_if_controller(controller)
        controller.clear_keycloak_cookies if controller.respond_to?(:clear_keycloak_cookies)
      end

      # Store the timestamp of the last successful token refresh in the session.
      # Used by recent_successful_refresh? to detect token-rotation race conditions.
      def record_refresh_timestamp(controller)
        return unless controller.respond_to?(:session)

        controller.session[:keycloak_last_refresh_at] = Time.now.to_i
      rescue StandardError
        # Non-fatal: worst case the race-condition guard is simply unavailable
      end

      # Returns true if a successful refresh occurred within REFRESH_RACE_WINDOW_SECONDS.
      # A 400/401 received during this window is almost certainly a token-rotation
      # race (another concurrent request already refreshed) rather than a genuine expiry.
      def recent_successful_refresh?(controller, window_seconds: REFRESH_RACE_WINDOW_SECONDS)
        return false unless controller.respond_to?(:session)

        last_at = controller.session[:keycloak_last_refresh_at].to_i
        last_at.positive? && (Time.now.to_i - last_at) < window_seconds
      rescue StandardError
        false
      end

      # Read a token from the Rails session (Redis-backed).
      # Used as fallback when the cookie is absent (e.g., oversized JWT dropped by browser).
      def reconstruct_token_from_session(controller, key)
        return nil unless controller.respond_to?(:session)

        controller.session[key].presence
      rescue StandardError
        nil
      end

      # Persist tokens to the Rails session (Redis-backed) so they survive even when the
      # corresponding cookies are too large for the browser to store (silent drop at ~4096 bytes).
      def save_tokens_to_session(controller, tokens)
        return unless controller.respond_to?(:session)

        session_id = controller.session.id.to_s.first(8)
        saved_at = tokens[:access_token].present?
        saved_rt = tokens[:refresh_token].present?
        controller.session[:keycloak_access_token] = tokens[:access_token] if tokens[:access_token]
        controller.session[:keycloak_refresh_token] = tokens[:refresh_token] if tokens[:refresh_token]
        Rails.logger.info "[Keycloak TokenService] save_tokens_to_session: session_id=#{session_id} " \
                          "access_token=#{saved_at ? "saved(#{tokens[:access_token].to_s.bytesize}b)" : "nil"} " \
                          "refresh_token=#{saved_rt ? "saved" : "nil"}"
      rescue StandardError => e
        Rails.logger.warn "[Keycloak TokenService] Failed to save tokens to session: #{e.message}"
      end
    end
  end
end
