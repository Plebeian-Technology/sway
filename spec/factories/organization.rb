FactoryBot.define do
  factory :organization do
    # @lat: [[jurisdiction-rules#A test fixture names a jurisdiction in full or not at all]]
    sequence(:name) { |n| "Taco Org #{n}" }
    # An absolute path, so the browser does not read "logo.svg" as relative to
    # the current page. On /organizations/:id/memberships/:id that would route
    # to the membership#show action with id=logo and format=svg, and return a
    # 500.
    icon_url { "/logo.svg" }
    sway_locale

    initialize_with { new({name:, icon_url:}) }
  end
end
