# frozen_string_literal: true

class KeycloakTokenSessionsController < Decidim::ApplicationController
  skip_before_action :verify_authenticity_token

  # POST /keycloak_token_login
  def create
    # --- Prendi il token dal body o dai parametri ---
    token = params[:token] || begin
      body = request.body.read
      JSON.parse(body)["token"] rescue nil
    end

    return head :unauthorized if token.blank?

    begin
      # --- Decodifica JWT (senza verifica firma: trusted token da parent) ---
      decoded = JWT.decode(token, nil, false).first
      email   = decoded["email"]
      return head :unauthorized if email.blank?

      # --- Cerca utente ---
      user = Decidim::User.find_by(email: email, organization: current_organization)

      unless user
        # --- Utente non esiste: segui il flusso Decidim/Keycloak standard ---
        render json: {
          status: "redirect",
          url: "/users/auth/keycloakopenid"
        } and return
      end

      # --- Aggiorna eventuali ruoli ---
      roles = decoded.dig("realm_access", "roles") || []
      user.update(admin: roles.include?("ADMIN") || roles.include?("SUPER_ADMIN"))

      # --- Login silenzioso ---
      sign_in(user, event: :authentication)
      Rails.logger.info "[KeycloakTokenSessions] User #{user.email} signed in successfully"

      # --- Risposta JSON ---
      render json: { status: "ok", user: user.email }

    rescue JWT::DecodeError => e
      Rails.logger.error "[KeycloakTokenSessions] Invalid JWT: #{e.message}"
      render json: { error: "Invalid token" }, status: :unauthorized
    rescue => e
      Rails.logger.error "[KeycloakTokenSessions] Keycloak login error: #{e.message}"
      render json: { error: e.message }, status: :unauthorized
    end
  end
end
