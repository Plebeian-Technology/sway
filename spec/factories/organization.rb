FactoryBot.define do
  factory :organization do
    name { "Taco Org" }
    icon_path { "logo.svg" }
    sway_locale

    initialize_with { new({name:, icon_path:}) }
  end
end
