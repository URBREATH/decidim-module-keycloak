# SPDX-License-Identifier: AGPL-3.0
# Copyright (c) 2025, European Commission. Licensed under the AGPL-3.0
# Authors:
# Gianfranco Cedro
# frozen_string_literal: true

module Decidim
  module Keycloak
    class LocaleSynchronizer
      def initialize(id_token, current_locale)
        @id_token = id_token
        @current_locale = current_locale
      end

      def self.sync_from_token(id_token, current_locale)
        new(id_token, current_locale).sync
      end

      def sync
        return nil if @id_token.blank?

        token_locale = extract_locale_from_token
        return nil if token_locale.blank?

        if token_locale == @current_locale
          nil # No change needed
        else
          token_locale
        end
      end

      private

      def extract_locale_from_token
        return nil if @id_token.blank?

        # CENTRALIZED: Uses Decidim::Keycloak::JwtParser
        available_locales = Decidim.available_locales
        user_locale = Decidim::Keycloak::JwtParser.extract_locale(@id_token, available_locales)

        user_locale
      rescue StandardError => e
        nil
      end
    end
  end
end
