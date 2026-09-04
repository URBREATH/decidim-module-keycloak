# SPDX-License-Identifier: AGPL-3.0
# Copyright (c) 2025, European Commission. Licensed under the AGPL-3.0
# Authors:
# Gianfranco Cedro
# frozen_string_literal: true

module Decidim
  module Keycloak
    # Centralized JWT token parsing and validation utilities
    # This module handles all JWT operations to prevent duplication
    class JwtParser
      # Parse JWT token and extract claims
      # @param jwt_token [String] The JWT token string
      # @return [Hash, nil] The claims hash or nil if invalid
      def self.parse_claims(jwt_token)
        return nil if jwt_token.blank?

        begin
          token_parts = jwt_token.split(".")
          return nil unless token_parts.length >= 2

          # Decode payload (second part)
          payload = Base64.decode64(token_parts[1].ljust((token_parts[1].length + 3) / 4 * 4, "="))
          JSON.parse(payload)
        rescue JSON::ParserError => e
          nil
        rescue StandardError => e
          nil
        end
      end

      # Extract expiry time from JWT token
      # @param jwt_token [String] The JWT token string
      # @return [Time, nil] The expiry time or nil if not present/invalid
      def self.extract_expiry(jwt_token)
        claims = parse_claims(jwt_token)
        return nil unless claims

        exp = claims["exp"]
        return nil unless exp

        # Handle both seconds and milliseconds timestamps
        # Keycloak can return timestamps in milliseconds (> 1 trillion)
        exp > 1_000_000_000_000 ? Time.zone.at(exp / 1000) : Time.zone.at(exp)
      rescue StandardError => e
        nil
      end

      # Check if token is locally expired (no network call)
      # @param jwt_token [String] The JWT token string
      # @return [Boolean] true if expired or invalid, false if still valid
      def self.locally_expired?(jwt_token)
        return true if jwt_token.blank?

        expiry_time = extract_expiry(jwt_token)
        return true unless expiry_time

        # Add 1-minute buffer to account for clock skew between servers
        # This prevents false positives due to slight time differences
        buffer_time = 1.minute
        expiry_time < (Time.zone.now + buffer_time)
      end

      def self.extract_locale(jwt_token, available_locales = nil)
        claims = parse_claims(jwt_token)
        return nil unless claims

        user_locale = extract_locale_from_claims(claims)
        return nil if user_locale.blank?

        validate_locale_against_available(user_locale, available_locales)
      end

      def self.extract_locale_from_claims(claims)
        claims["locale"] ||
          claims["preferred_locale"] ||
          claims["ui_locales"]&.first
      end

      def self.validate_locale_against_available(user_locale, available_locales)
        return user_locale.to_s unless available_locales

        locales_list = available_locales.map(&:to_s)

        # Try exact match
        return user_locale.to_s if locales_list.include?(user_locale.to_s)

        # Try language code only (e.g., 'en' from 'en-US')
        language_code = user_locale.to_s.split("-").first
        return language_code if locales_list.include?(language_code)

        nil
      end

      # Validate basic JWT structure and required claims
      # @param jwt_token [String] The JWT token string
      # @return [Boolean] true if valid structure, false otherwise
      def self.valid_structure?(jwt_token)
        return false if jwt_token.blank?

        claims = parse_claims(jwt_token)
        return false unless claims

        # Check for required claims
        claims["sub"].present? && claims["email"].present?
      rescue StandardError => e
        false
      end
    end
  end
end
