class KeycloakTokenSessionsController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    token = params[:token]
    return head :unauthorized unless token

    # Decodifica il token senza verificarlo (per test)
    decoded = JWT.decode(token, nil, false).first
    email = decoded["email"]

    user = Decidim::User.find_by(email: email)
    return head :unauthorized unless user

    sign_in(user)
    render json: { status: "ok", user: user.email }
  rescue => e
    render json: { error: e.message }, status: :unauthorized
  end
end
