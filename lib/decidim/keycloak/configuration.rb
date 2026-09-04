# SPDX-License-Identifier: AGPL-3.0
# Copyright (c) 2025, European Commission. Licensed under the AGPL-3.0
# Authors:
# Gianfranco Cedro
# frozen_string_literal: true

module Decidim
  module Keycloak
    # Centralized configuration for Keycloak authentication
    # Eliminates duplication across concerns and service objects
    module Configuration
      class << self
        def config
          @config ||= {
            site: ENV.fetch("OMNIAUTH_KEYCLOAK_SITE", nil),
            realm: ENV["OMNIAUTH_KEYCLOAK_REALM"] || "master",
            client_id: ENV.fetch("OMNIAUTH_KEYCLOAK_CLIENT_ID", nil),
            client_secret: ENV.fetch("OMNIAUTH_KEYCLOAK_CLIENT_SECRET", nil)
          }
        end

        def site
          config[:site]
        end

        def realm
          config[:realm]
        end

        def client_id
          config[:client_id]
        end

        def client_secret
          config[:client_secret]
        end

        def valid?
          site.present? && client_id.present? && client_secret.present?
        end

        # Validate and return the authorization URL for Keycloak
        # Returns nil if the configuration is invalid
        def authorization_url(redirect_uri:, state:)
          return nil unless valid?

          begin
            uri = URI.parse(site)

            # Validate URI scheme and host
            unless (uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)) && uri.host.present?
              return nil
            end

            # Build the base URL from validated components
            base = "#{uri.scheme}://#{uri.host}"
            base += ":#{uri.port}" unless uri.port == uri.default_port

            # Construct authorization URL with escaped parameters
            auth_params = {
              client_id: CGI.escape(client_id),
              redirect_uri: CGI.escape(redirect_uri),
              response_type: "code",
              scope: "openid profile email",
              state: CGI.escape(state)
            }

            query_string = auth_params.map { |k, v| "#{k}=#{v}" }.join("&")
            "#{base}/realms/#{CGI.escape(realm)}/protocol/openid-connect/auth?#{query_string}"
          rescue URI::InvalidURIError => e
            nil
          end
        end

        # Clear cached config (useful for testing)
        def reset!
          @config = nil
        end
      end
    end
  end
end
