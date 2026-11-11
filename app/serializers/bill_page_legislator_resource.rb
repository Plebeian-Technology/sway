# frozen_string_literal: true

# @lat: [[legislator-photo-prefetch#Prefetching a reader's own legislator photos#Why the photo attachment and blob are preloaded]]
class BillPageLegislatorResource < ApplicationResource
  attributes :id, :sway_locale_id, :external_id

  attribute :active do |legislator|
    legislator.serving?
  end

  attributes :link, :email, :title, :first_name, :last_name

  attribute :full_name do |legislator|
    "#{legislator.first_name} #{legislator.last_name}"
  end

  attributes :phone, :fax, :party

  attribute :photo_url do |legislator|
    MirroredAssetUrl.for(legislator.photo, fallback: legislator.photo_url)
  end

  attribute :district do |legislator|
    district = legislator.district
    district && BillPageDistrictResource.new(district).serializable_hash
  end

  attributes :twitter
end
