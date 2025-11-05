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
        Rails.logger.info "[KeycloakTokenSessions] User not found → attempting auto-registration"
        user = register_user_from_token!(decoded, organization)

        unless user
          Rails.logger.warn "[KeycloakTokenSessions] Auto-registration failed → falling back to Keycloak flow"
          render json: {
            status: "redirect",
            url: "/users/auth/keycloakopenid?embedded_login=true"
          }, status: :ok and return
        end
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

  def register_user_from_token!(decoded_token, organization)
    return unless organization

    email = decoded_token["email"].to_s.strip
    return if email.blank?

    name =
      decoded_token["name"].presence ||
      decoded_token["given_name"].presence ||
      decoded_token["preferred_username"].presence ||
      email.split("@").first

    password = SecureRandom.base58(32)
    locale =
      decoded_token["locale"].presence ||
      organization.default_locale.presence ||
      I18n.default_locale.to_s

    ensure_terms_page_copy!(organization, locale)

    form = Decidim::RegistrationForm
      .from_params(
        name: name,
        email: email,
        password: password,
        tos_agreement: true,
        newsletter: false,
        current_locale: locale
      )
      .with_context(current_organization: organization)

    created_user = nil
    Decidim::CreateRegistration.call(form) do
      on(:ok) do |user|
        created_user = user
        if created_user.respond_to?(:confirm) && !created_user.confirmed?
          created_user.confirm
        end

        created_user.update_columns(
          accepted_tos_version: nil,
          locale: locale
        )

        Rails.logger.info "[KeycloakTokenSessions] Auto-registered user #{user.email}"
      end

      on(:invalid) do
        Rails.logger.error "[KeycloakTokenSessions] Registration form invalid: #{form.errors.full_messages.join(', ')}"
      end
    end

    created_user
  rescue => e
    Rails.logger.error "[KeycloakTokenSessions] Auto-registration error: #{e.message}"
    nil
  end

  def ensure_terms_page_copy!(organization, locale)
    page = Decidim::StaticPage.find_by(slug: "terms-of-service", organization:)
    return unless page

    locale = locale.to_s
    title_translations = page.title || {}
    content_translations = page.content || {}

    current_title = title_translations[locale].to_s.strip
    current_content = content_translations[locale].to_s.strip

    title_needs_update = current_title.blank? || current_title.match?(/\ADefault title for Terms of service/i)
    content_needs_update = current_content.blank? || current_content.match?(/add meaningful content/i)

    if title_needs_update || content_needs_update
      fallback_title = I18n.t("decidim.pages.terms_of_service.fallback_title", default: "Terms of Service")
      fallback_body = I18n.t(
        "decidim.pages.terms_of_service.fallback_body_html",
        default: "<p>Please review the Terms of Service below and press Accept to continue.</p>"
      )

      page.update!(
        title: title_translations.merge(locale => title_needs_update ? fallback_title : current_title),
        content: content_translations.merge(locale => content_needs_update ? fallback_body : current_content)
      )
    end

    summary_block = Decidim::ContentBlock
                     .published
                     .for_scope(:static_page, organization:)
                     .where(manifest_name: "summary", scoped_resource_id: page.id)
                     .first

    return unless summary_block

    raw_settings = summary_block.read_attribute(:settings) || {}
    summaries = raw_settings["summary"] || {}
    current_summary = summaries[locale].to_s.strip

    return unless current_summary.blank? || current_summary.match?(/meaningful summary/i)

    fallback_summary = I18n.t(
      "decidim.pages.terms_of_service.fallback_summary",
      default: "Please read the terms below and press Accept to continue."
    )

    summary_block.update!(
      settings: raw_settings.merge(
        "summary" => summaries.merge(locale => fallback_summary)
      )
    )
  end
end
