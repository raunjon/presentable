# frozen_string_literal: true

# Stand-in for cancancan's exception class (the gem doesn't depend on
# cancancan). Defined before RescuesController includes StandardRescues so the
# CanCan handler is registered.
module CanCan
  class AccessDenied < StandardError; end
end

class RescuesController < ActionController::Base
  include Presentable::StandardRescues

  def not_found
    Lead.find(-1)
  end

  def access_denied
    raise CanCan::AccessDenied
  end

  def unhandled
    raise ArgumentError, "not rescued"
  end
end
