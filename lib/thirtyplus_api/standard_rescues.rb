# frozen_string_literal: true

module ThirtyplusApi
  # The rescue_from handlers every service's Api::BaseController declares:
  #
  #   ActiveRecord::RecordNotFound -> 404 record_not_found(exception.message)
  #   CanCan::AccessDenied         -> 403 unauthorized_error (only when
  #                                   CanCanCan is loaded before the include)
  module StandardRescues
    extend ActiveSupport::Concern
    include ErrorResponses

    included do
      rescue_from ActiveRecord::RecordNotFound do |exception|
        record_not_found(exception.message)
      end

      if defined?(CanCan::AccessDenied)
        rescue_from CanCan::AccessDenied do
          unauthorized_error
        end
      end
    end
  end
end
