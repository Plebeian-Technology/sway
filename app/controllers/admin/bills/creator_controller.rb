# frozen_string_literal: true

module Admin
  module Bills
    class CreatorController < ApplicationController
      before_action :verify_is_admin

      def index
        render inertia: "BillOfTheWeekCreatorPage"
      end
    end
  end
end
