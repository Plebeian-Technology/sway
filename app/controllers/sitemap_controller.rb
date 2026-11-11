class SitemapController < ApplicationController
  skip_before_action :authenticate_sway_user!

  # @lat: [[sitemap-forced-xml-format#Why GET /sitemap.xml forces the XML format]]
  # @lat: [[request-locale-selection#Anonymous fallback locale lists are filtered to declared locales]]
  def index
    @bills = Bill.where(active: true)
    @legislators = Legislator.serving
    @sway_locales = SwayLocale.declared
    render formats: :xml, layout: false
  end
end
