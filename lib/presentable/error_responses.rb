# frozen_string_literal: true

module Presentable
  # Error envelope helpers: every method renders
  #   { error: { message:, status: }, success: false }
  # Moved verbatim from the original ErrorResponseActions (generic part only).
  # Service-specific errors stay in each service; the session/token
  # errors shared by all services live in Presentable::SessionErrors.
  module ErrorResponses
    ERROR_RESPONSE_ACTIONS = %(authentication_error
                               device_mismatch_error
                               token_expired_error
                               forbidden_error
                               resource_not_found
                               page_not_found
                               not_implmented
                               route_not_found
                               method_not_allowed).freeze

    include HttpStatusCode

    def response_with(message,status)
      error = { error: { message: message, status: status }, success: false }
      render_response(error,status)
    end

    def render_validation_errors(errors)
      error = { error: { message: errors.full_messages.join(', ').to_s, status: validation_error_status_code },
                success: false }
      render_response(error, validation_error_status_code)
    end

    def render_admin_validation_error(errors)
      error = errors.full_messages.join("\n")
      render_response(error, validation_error_status_code)
    end

    def authentication_error
      response_with('You must login to continue.', authentication_status_code)
    end

    def unauthorized_error
      response_with('You are not authorized to view or edit this content.', forbidden_status_code)
    end

    def forbidden_error
      response_with('Forbidden', forbidden_status_code)
    end

    def record_not_found(message)
      response_with(message,not_found_status_code)
    end

    def page_not_found(message)
      response_with(message,not_found_status_code)
    end

    def server_error(message)
      response_with(message, server_error_status_code)
    end

    def not_implemented(allowed_methods)
      method_not_allowed(allowed_methods, 'Not Implemented', not_implemented_status_code)
    end

    def method_not_allowed(allowed_methods, message = 'Method Not Allowed', status = method_not_allowed_status_code)
      response.headers['Allow'] ||= allowed_methods.map { |method_symbol| method_symbol.to_s.upcase } * ', '
      response_with(message, status)
    end

    def bad_request(message,value)
        error = { error: { value: value, message: message, status: bad_request_status_code }, success: false }
        render_response(error, bad_request_status_code)
    end

    def route_not_found
      method = request.env['REQUEST_METHOD'].downcase.to_sym
      path = request.env['PATH_INFO']
      # Route was not recognized. Try to find out why (maybe wrong verb).

      allows = ActionDispatch::Routing::HTTP_METHODS.select do |verb|
        begin
          match = Rails.application.routes.recognize_path(path, method: verb)
          match[:action] != 'route_not_found'
        rescue ActionController::RoutingError
          nil
        end
      end

      if !allows.empty? && !ActionDispatch::Routing::HTTP_METHODS.include?(method)
        not_implemented allows
      elsif !allows.empty?
        method_not_allowed allows
      else
        if Rails.configuration.consider_all_requests_local
          response.headers['X-Cascade'] = 'pass'
          render json: true, status: 404
        else
          page_not_found("Path '#{path}' not found")
        end
        # page_not_found("Path '#{path}' not found")
      end
    end

    private
    include ActionController::MimeResponds

    def render_response(error, status)
      render_from_hash(error, status)
    end

    def render_from_hash(hash, status = success_status_code)
      respond_to do |format|
        format.html{ render json: hash, status: status}
        format.xml{  render xml: hash, status: status}
        format.csv{ render csv: hash, status: status}
        format.json{ render json: hash, status: status, include: @includes, root: 'true'}
        format.pdf{ render pdf: hash, status: status}
      end
    end
  end
end
