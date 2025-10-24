class KeycloakTokenSessionsController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    token = params[:token]
    return head :unauthorized unless token

    begin
      decoded = JWT.decode(token, nil, false).first
      Rails.logger.info "Decoded Keycloak token: #{decoded.inspect}"

      email = decoded["email"]
      roles = decoded.dig("realm_access", "roles") || []

      user = Decidim::User.find_by(email: email)
      return head :unauthorized unless user

      if roles.include?("ADMIN") || roles.include?("SUPER_ADMIN")
        # aggiorna admin e il timestamp della password ad ogni promozione/login
        user.update(
          admin: true,
          password_updated_at: Time.current
        )
        Rails.logger.info "User #{user.email} set as admin with updated password timestamp"
      else
        # Se vuoi mantenere sempre il timestamp aggiornato anche per user non-admin:
        user.update(password_updated_at: Time.current)
      end

      sign_in(user)
      render json: { status: "ok", user: user.email }
    rescue => e
      Rails.logger.error "Keycloak login error: #{e.message}"
      render json: { error: e.message }, status: :unauthorized
    end
  end
end
