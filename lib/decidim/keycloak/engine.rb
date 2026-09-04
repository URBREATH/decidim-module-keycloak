# frozen_string_literal: true

require "omniauth/strategies/keycloak-openid"

module Decidim
  module Keycloak
    # This is the engine that runs on the public interface of keycloak.
    class Engine < ::Rails::Engine
      isolate_namespace Decidim::Keycloak

      initializer "decidim.keycloak.middleware" do |app|
        app.config.middleware.use OmniAuth::Builder do
          provider :keycloak_openid, setup: lambda { |env|
            request = Rack::Request.new(env)
            organization = Decidim::Organization.find_by(host: request.host)
            config = organization.enabled_omniauth_providers[:keycloakopenid]
            site = config[:site].to_s.chomp("/")
            realm = config[:realm].to_s
            # This Keycloak installation uses the legacy /auth context. Keep a
            # custom base URL available but default to /auth when it is blank.
            base_url = config[:base_url].presence || "/auth"
            callback_url = request.url.split("?").first + "/callback"

            env["omniauth.strategy"].options[:client_id] = config[:client_id]
            env["omniauth.strategy"].options[:client_secret] = config[:client_secret]
            env["omniauth.strategy"].options[:client_options] = {
              site: site,
              realm: realm,
              base_url: base_url,
              authorize_url: "#{base_url}/realms/#{realm}/protocol/openid-connect/auth",
              token_url: "#{base_url}/realms/#{realm}/protocol/openid-connect/token",
              redirect_uri: callback_url
            }
          }
        end
      end

         initializer "keycloak.add_routes" do |app|
            app.routes.append do
              post "/keycloak_token_login", to: "keycloak_token_sessions#create"
            end
      end

      config.to_prepare do
        class OmniAuth::Strategies::KeycloakOpenId
          uid { raw_info["preferred_username"] }

          info do
            {
              nickname: raw_info["preferred_username"],
              name: raw_info["name"],
              email: raw_info["email"]
            }
          end

          def extra
            extra = {
              raw_info: raw_info,
              id_token: access_token.params["id_token"],
              access_token: access_token.token,
              refresh_token: access_token.params["refresh_token"],
              token_expires_in: access_token.params["expires_in"]
            }.compact

            token_claims = Decidim::Keycloak::JwtParser.parse_claims(access_token.token) || {}
            client_roles = raw_info.dig("resource_access", options.client_id.to_s, "roles") ||
                           token_claims.dig("resource_access", options.client_id.to_s, "roles") || []
            realm_roles = raw_info.dig("realm_access", "roles") ||
                          token_claims.dig("realm_access", "roles") || []
            extra[:keycloak_roles] = client_roles if client_roles.present?
            extra[:keycloak_realm_roles] = realm_roles if realm_roles.present?
            extra[:is_decidim_admin] = raw_info["is_decidim_admin"] == true ||
                                        token_claims["is_decidim_admin"] == true ||
                                        raw_info["admin"] == true ||
                                        token_claims["admin"] == true ||
                                        client_roles.any? { |role| %w[Admin ADMIN SUPER_ADMIN].include?(role) } ||
                                        realm_roles.any? { |role| %w[Admin ADMIN SUPER_ADMIN].include?(role) }
            extra
          end
        end
      end

      initializer "decidim.keycloak.devise_extension" do
        config.to_prepare do
          controller = Decidim::Devise::OmniauthRegistrationsController
          controller.prepend(Decidim::Keycloak::DeviseExtension) unless controller < Decidim::Keycloak::DeviseExtension
        end
      end

    end
  end
end
