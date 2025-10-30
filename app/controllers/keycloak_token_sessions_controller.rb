# frozen_string_literal: true

class KeycloakTokenSessionsController < ApplicationController
  skip_before_action :verify_authenticity_token

  # POST /keycloak_token_login
  def create
    token = params[:token] || begin
      body = request.body.read
      JSON.parse(body)["token"] rescue nil
    end
    return head :unauthorized unless token

    begin
      decoded = JWT.decode(token, nil, false).first
      email = decoded["email"]
      return head :unauthorized if email.blank?

      # ✅ Forza sempre l'organizzazione giusta (evita bug iframe)
      organization =
        Decidim::Organization.find_by(host: "decidim-2-dev.urbreath.tech") ||
        Decidim::Organization.find_by(host: request.host) ||
        Decidim::Organization.first

      Rails.logger.info "[KeycloakTokenSessions] Using organization: #{organization&.host || 'nil'}"

      user = Decidim::User.find_by(email: email, organization: organization)

      unless user
        Rails.logger.info "[KeycloakTokenSessions] User not found → proceeding with Keycloak registration flow"
        render json: {
          status: "new_user",
          url: "/users/auth/keycloakopenid?embedded_login=true"
        }, status: :ok and return
      end

      roles = decoded.dig("realm_access", "roles") || []
      user.update(admin: roles.include?("ADMIN") || roles.include?("SUPER_ADMIN"))

      sign_in(user)
      Rails.logger.info "[KeycloakTokenSessions] User #{user.email} signed in successfully"

      render json: { status: "ok", user: user.email }

    rescue JWT::DecodeError => e
      Rails.logger.error "[KeycloakTokenSessions] Invalid JWT: #{e.message}"
      render json: { error: "Invalid token" }, status: :unauthorized
    rescue => e
      Rails.logger.error "[KeycloakTokenSessions] Keycloak login error: #{e.message}"
      render json: { error: e.message }, status: :unauthorized
    end
  end

  private
end
