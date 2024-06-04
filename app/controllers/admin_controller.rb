class AdminController < ApplicationController
  before_action :verify_is_admin
end
