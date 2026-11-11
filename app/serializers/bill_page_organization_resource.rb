# frozen_string_literal: true

class BillPageOrganizationResource < ApplicationResource
  attributes :id, :sway_locale_id, :name

  attribute :icon_url do |organization|
    organization.mirrored_icon_url
  end
end
