class SitemapController < ApplicationController
  skip_before_action :authenticate_user!

  def index
    @bills = Bill.all.includes(:sway_locale) # Replace YourModel with your actual model
    @legislators = Legislator.all.includes(district: :sway_locale) # Replace YourModel with your actual model
    @sway_locales = SwayLocale.all
    respond_to do |format|
      format.xml { render layout: false } # Render without layout
    end
  end
end
