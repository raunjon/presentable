# frozen_string_literal: true

class LeadsController < ActionController::Base
  include Presentable::Controller

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
# the child includes Presentable::Controller.
class PagyParentController < ActionController::Base
  include Pagy::Backend
end

class LayeredLeadsController < PagyParentController
  include Presentable::Controller

  def index
    set_pagy_and_present(Lead.order(:id))
  end
end

# A service that lowers the per_page cap (GEM-5).
class CappedLeadsController < ActionController::Base
  include Presentable::Controller
  self.max_per_page = 4

  def index
    set_pagy_and_present(Lead.order(:id))
  end
end
