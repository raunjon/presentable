# frozen_string_literal: true

module ThirtyplusApi
  module HttpStatusCode
    def success_status_code
      200
    end

    def bad_request_status_code
      400
    end

    def unauthorized_status_code
      401
    end

    def authentication_status_code
      403
    end

    def forbidden_status_code
      403
    end

    def not_found_status_code
      404
    end

    def method_not_allowed_status_code
      405
    end

    def validation_error_status_code
      422
    end

    def server_error_status_code
      500
    end

    def not_implemented_status_code
      501
    end
  end
end
