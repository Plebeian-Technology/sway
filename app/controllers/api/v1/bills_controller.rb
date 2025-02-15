class Api::V1::BillsController < BillsController
  before_action :doorkeeper_authorize! # Requires access token for all actions
  respond_to    :json

  def index
    binding.pry
    super
  end
end
