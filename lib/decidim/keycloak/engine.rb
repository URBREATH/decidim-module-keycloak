# frozen_string_literal: true

require "omniauth/strategies/keycloak-openid"

module Decidim
  module Keycloak
    # This is the engine that runs on the public interface of keycloak.
    class Engine < ::Rails::Engine
      isolate_namespace Decidim::Keycloak

      initializer "decidim.keycloak.middleware" do |app|
        omniauth_config = Rails.application.secrets[:omniauth]
        next if omniauth_config[:keycloakopenid].blank?

        app.config.middleware.use OmniAuth::Builder do
          provider :keycloak_openid, setup: lambda { |env|
            request = Rack::Request.new(env)
            organization = Decidim::Organization.find_by(host: request.host)
            config = organization.enabled_omniauth_providers[:keycloakopenid]
            env["omniauth.strategy"].options[:client_id] = config[:client_id]
            env["omniauth.strategy"].options[:client_secret] = config[:client_secret]       
            env["omniauth.strategy"].options[:client_options] = { site: config[:site], realm: config[:realm], base_url: config[:base_url], redirect_uri: request.url.split("?").first + "/callback" } # remove the language parameter from the callback url
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
        end
      end

    end
  end
end
