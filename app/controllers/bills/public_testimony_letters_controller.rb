# frozen_string_literal: true

# @lat: [[testimony-letters#Reading the letters inside a testimony bundle#Browsing constituent testimony in the modal]]
module Bills
  class PublicTestimonyLettersController < ApplicationController
    skip_before_action :authenticate_sway_user!, only: %i[index]

    def index
      bill = Bill.unscope(where: :archived_at).find(params[:bill_id])

      respond_to do |format|
        format.json do
          if current_user
            entries = Testimony::BrowsableLetters.for_bill(bill)
            render json: PublicTestimonyLetterResource.new(entries).serializable_hash
          else
            render json: nil
          end
        end
      end
    end
  end
end
