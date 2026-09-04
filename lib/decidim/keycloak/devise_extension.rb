# frozen_string_literal: true

module Decidim
  module Keycloak
    # Persists the OIDC tokens issued during a successful Keycloak callback.
    # The application authentication concern uses these tokens to keep the
    # Keycloak session alive after Decidim signs the user in.
    module DeviseExtension
      def create
        auth_data = request.env["omniauth.auth"]
        result = super

        persist_keycloak_tokens(auth_data) if keycloak_auth?(auth_data)

        result
      end

      private

      def keycloak_auth?(auth_data)
        auth_data&.provider == "keycloakopenid" && current_user.present?
      end

      def persist_keycloak_tokens(auth_data)
        tokens = {
          access_token: auth_data.extra["access_token"] || auth_data.credentials["token"],
          refresh_token: auth_data.extra["refresh_token"] || auth_data.credentials["refresh_token"],
          id_token: auth_data.extra["id_token"],
          expires_in: auth_data.extra["token_expires_in"] || auth_data.credentials["expires_in"]
        }
        return if tokens[:access_token].blank?

        Decidim::Keycloak::TokenService.new.save_tokens_to_cookies(cookies, tokens, request.host)
        session[:keycloak_access_token] = tokens[:access_token]
        session[:keycloak_refresh_token] = tokens[:refresh_token] if tokens[:refresh_token].present?
        session[:keycloak_authenticated] = true
        synchronize_admin_role(auth_data)
      end

      def synchronize_admin_role(auth_data)
        return unless auth_data.extra.key?("is_decidim_admin")

        is_admin = auth_data.extra["is_decidim_admin"] == true
        current_user.update!(admin: is_admin) if current_user.admin? != is_admin
      end
    end
  end
end
