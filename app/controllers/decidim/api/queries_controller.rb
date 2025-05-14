module Decidim
  module Api
    class QueriesController < Api::ApplicationController
      require "jwt"
      require "net/http"
      require "uri"
      require "json"

      def create
        variables = prepare_variables(params[:variables])
        query = params[:query]
        operation_name = params[:operationName]

        result = Schema.execute(
          query,
          variables: variables,
          context: {
            current_organization: current_organization,
            current_user: current_user
          },
          operation_name: operation_name
        )

        render json: result
      rescue StandardError => e
        logger.error e.message
        logger.error e.backtrace.join("\n")

        message = Rails.env.development? ? { message: e.message, backtrace: e.backtrace } : { message: "Internal Server error" }
        render json: { errors: [message], data: {} }, status: :internal_server_error
      end

      private

      def prepare_variables(variables_param)
        case variables_param
        when String
          variables_param.present? ? JSON.parse(variables_param) : {}
        when Hash
          variables_param
        when ActionController::Parameters
          variables_param.to_unsafe_hash
        when nil
          {}
        else
          raise ArgumentError, "Unexpected parameter: #{variables_param}"
        end
      end

      def current_user
        super || user_from_token
      end

      def jwks_keys
        uri = URI("https://keycloak-dev.urbreath.tech/auth/realms/decidim/protocol/openid-connect/certs")
        response = Net::HTTP.get(uri)
        JSON.parse(response)["keys"]
      end
      

      def user_from_token
        auth_header = request.headers["Authorization"]
        return nil unless auth_header&.start_with?("Bearer ")

        token = auth_header.split(" ").last
        jwks = JWT::JWK::Set.new(jwks_keys)
        decoded_token = JWT.decode(token, nil, true, algorithms: ["RS256"], jwks: jwks)

        email = decoded_token[0]["email"]
        Decidim::User.find_by(email: email)
      rescue JWT::DecodeError, OpenSSL::PKey::RSAError => e
        Rails.logger.warn("JWT decode failed: #{e.message}")
        nil
      end
    end
  end
end
