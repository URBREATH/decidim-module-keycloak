# frozen_string_literal: true

class KeycloakTokenSessionsController < ApplicationController
  skip_before_action :verify_authenticity_token

  # POST /keycloak_token_login
  def create
    # --- Prendi il token dal body o dai parametri ---
    token = params[:token] || begin
      body = request.body.read
      JSON.parse(body)["token"] rescue nil
    end

    unless token
      Rails.logger.warn "[KeycloakTokenSessions] No token provided"
      return head :unauthorized
    end

    begin
      # --- Decodifica JWT senza verifica della signature (assumendo trusted dal parent) ---
      decoded = JWT.decode(token, nil, false).first
      Rails.logger.info "[KeycloakTokenSessions] Decoded JWT: #{decoded.inspect}"

      email = decoded["email"]
      return head :unauthorized if email.blank?

      # --- Cerca utente esistente ---
      user = Decidim::User.find_by(email: email)

      unless user
        # --- Nuovo utente → redirect completo verso OmniAuth Keycloak ---
        Rails.logger.info "[KeycloakTokenSessions] User not found, redirecting to /users/auth/keycloakopenid"
        render json: { status: "redirect", url: "/users/auth/keycloakopenid?embedded=true" } and return
      end

      # --- Aggiorna timestamp password e ruoli admin ---
      roles = decoded.dig("realm_access", "roles") || []
      if roles.include?("ADMIN") || roles.include?("SUPER_ADMIN")
        user.update(admin: true, password_updated_at: Time.current)
      else
        user.update(password_updated_at: Time.current)
      end

      # --- Login silenzioso dell'utente ---
      sign_in(user)
      Rails.logger.info "[KeycloakTokenSessions] User #{user.email} signed in successfully"

      # --- Risposta JSON per JS embedded ---
      render json: { status: "ok", user: user.email }

    rescue JWT::DecodeError => e
      Rails.logger.error "[KeycloakTokenSessions] JWT decode error: #{e.message}"
      render json: { error: "Invalid token" }, status: :unauthorized
    rescue => e
      Rails.logger.error "[KeycloakTokenSessions] Keycloak login error: #{e.message}"
      render json: { error: e.message }, status: :unauthorized
    end
  end
end
