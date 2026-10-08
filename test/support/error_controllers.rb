# frozen_string_literal: true

class ErrorsController < ActionController::Base
  include ThirtyplusApi::SessionErrors

  def validation
    errors = ActiveModel::Errors.new(Lead.new)
    errors.add(:name, :blank)
    render_validation_errors(errors)
  end

  def not_found
    record_not_found("Lead not found")
  end

  def bad
    bad_request("Device ID not found", "device_id")
  end

  def not_allowed
    method_not_allowed([:get, :post])
  end

  def unauthorized
    unauthorized_error
  end

  def authentication
    authentication_error
  end

  def guest
    guest_authentication_error
  end

  def expired
    token_expired_error
  end

  def guest_expired
    guest_token_expired_error
  end
end
