# frozen_string_literal: true

class LeadsController < ActionController::Base
  include ThirtyplusApi::Presentable

  def index
    set_pagy_and_present(Lead.order(:id))
  end

  def show
    present Lead.find(params[:id])
  end

  def with_metadata
    present_object_with_metadata(Lead.order(:id).to_a, { filters_applied: true })
  end
end

# Mirrors operator_service: the parent controller includes Pagy::Backend and
# the child includes Presentable.
class PagyParentController < ActionController::Base
  include Pagy::Backend
end

class LayeredLeadsController < PagyParentController
  include ThirtyplusApi::Presentable

  def index
    set_pagy_and_present(Lead.order(:id))
  end
end
