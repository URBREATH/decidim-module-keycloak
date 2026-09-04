# SPDX-License-Identifier: AGPL-3.0
# Copyright (c) 2025, European Commission. Licensed under the AGPL-3.0
# Authors:
# Gianfranco Cedro
# frozen_string_literal: true

module Decidim
  module Keycloak
    # Detects cross-tool SSO navigation within the same domain.
    # Used to trigger auto-login when users navigate between tools
    # that share the same Keycloak authentication domain.
    #
    # @example
    #   CrossToolDetector.from_same_domain?(
    #     referer: "https://chatbot.ldttoolbox.app/",
    #     current_host: "part-int.ldttoolbox.app",
    #     decidim_host: "part-int.ldttoolbox.app"
    #   )
    #   # => true (same base domain, different subdomain)
    #
    class CrossToolDetector
      class << self
        # Check if the request is coming from another tool in the same domain
        #
        # @param referer [String] The HTTP referer header
        # @param current_host [String] The current request host
        # @param decidim_host [String, nil] The configured Decidim host (from ENV)
        # @return [Boolean] true if cross-tool navigation detected
        def from_same_domain?(referer:, current_host:, decidim_host: nil)
          return false if referer.blank?

          referer_uri = URI.parse(referer)
          decidim_host ||= current_host

          # Avoid loops: skip if referer is from the same Decidim instance
          return false if same_host?(referer_uri.host, decidim_host, current_host)

          # Check if referer is from same base domain but different subdomain
          base_domain = extract_base_domain(decidim_host)
          return false unless base_domain

          if different_subdomain_same_domain?(referer_uri.host, current_host, base_domain)
                              "#{referer_uri.host} → #{current_host} (domain: #{base_domain})"
            return true
          end

          false
        rescue URI::InvalidURIError
          false
        end

        private

        # Check if the referer host matches Decidim or current host
        def same_host?(referer_host, decidim_host, current_host)
          return true if referer_host == decidim_host
          return true if referer_host == current_host

          false
        end

        # Extract base domain from host (e.g., "part-int.ldttoolbox.app" → ".ldttoolbox.app")
        def extract_base_domain(host)
          return nil if host.blank?

          parts = host.split(".")
          return nil unless parts.length >= 2

          ".#{parts[-2]}.#{parts[-1]}"
        end

        # Check if referer is from different subdomain but same base domain
        def different_subdomain_same_domain?(referer_host, current_host, base_domain)
          return false if referer_host.blank?
          return false if referer_host == current_host

          referer_host.end_with?(base_domain)
        end
      end
    end
  end
end
