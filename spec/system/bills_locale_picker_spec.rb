# frozen_string_literal: true

require "rails_helper"

# @lat: [[reader-control-browser-tests#Reader control browser tests]]
RSpec.describe "Bills locale picker", type: :system, js: true do
  # @lat: [[reader-control-browser-tests#Reader control browser tests#Bills locale selection#The bills picker switches the visible list between locales]]
  it "switches the visible bill list to the selected locale" do
    baltimore = create(:sway_locale, :baltimore)
    maryland = create(:sway_locale, :maryland)
    baltimore_district = create(:district, sway_locale: baltimore, name: "Baltimore Test District")
    maryland_district = create(:district, sway_locale: maryland, name: "Maryland Test District")
    baltimore_legislator = create(:legislator, district: baltimore_district)
    maryland_legislator = create(:legislator, district: maryland_district)
    baltimore_bill = create(
      :bill,
      sway_locale: baltimore,
      legislator: baltimore_legislator,
      title: "Baltimore Only List Bill"
    )
    maryland_bill = create(
      :bill,
      sway_locale: maryland,
      legislator: maryland_legislator,
      title: "Maryland Only List Bill"
    )

    visit "/bills?sway_locale_id=#{baltimore.id}"

    visible_bill_list = find("p", text: /\AShowing /, visible: :visible).find(:xpath, "..")
    within(visible_bill_list) do
      expect(page).to have_text(:visible, baltimore_bill.title, wait: 20)
      expect(page).to have_no_text(:visible, maryland_bill.title)
    end

    find("select#v2-bills-locale").select(maryland.human_name)

    updated_visible_bill_list = find("p", text: /\AShowing /, visible: :visible).find(:xpath, "..")
    within(updated_visible_bill_list) do
      expect(page).to have_text(:visible, maryland_bill.title, wait: 20)
      expect(page).to have_no_text(:visible, baltimore_bill.title)
    end
  end
end
