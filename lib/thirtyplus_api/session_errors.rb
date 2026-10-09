# frozen_string_literal: true

module ThirtyplusApi
  # Session/token errors shared by every service that verifies the gateway JWT.
  module SessionErrors
    include ErrorResponses

    def token_expired_error
      response_with('Session expired, please login again', unauthorized_status_code)
    end

    def guest_token_expired_error
      response_with('Guest session expired, please login again', unauthorized_status_code)
    end

    def guest_authentication_error
      response_with('User or Guest User not found', unauthorized_status_code)
    end

    def invalid_token_error
      response_with('Invalid session, please login again', unauthorized_status_code)
    end
  end
end
