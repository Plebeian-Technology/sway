FactoryBot.define do
  factory :organization do
    name { "Taco Org" }
    icon_url { "logo.svg" }
    sway_locale

    initialize_with { new({ name:, icon_url: }) }
  end
end
