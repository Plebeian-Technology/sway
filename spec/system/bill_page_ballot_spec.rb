# frozen_string_literal: true

require "rails_helper"

# @lat: [[user-vote-submission#Themed web vote controls#Where the default control sits]]
RSpec.describe "Bill page ballot", type: :system, js: true do
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:user) { create(:user, :sway_admin) }
  let(:bill) do
    create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      title: "Department of Consumer Protection and Business Licensing"
    )
  end

  before { create(:user_legislator, user: user, legislator: legislator) }

  def landmarks
    page.evaluate_script(<<~JS)
      (() => {
        const read = (testid) => {
          const el = document.querySelector(`[data-testid='${testid}']`);
          if (!el) return null;
          const rect = el.getBoundingClientRect();
          return { left: rect.left, right: rect.right, top: rect.top + window.scrollY, bottom: rect.bottom + window.scrollY };
        };
        return {
          title: read("bill-title"),
          ballot: read("bill-ballot"),
          score: read("score-panel"),
          viewportHeight: window.innerHeight
        };
      })()
    JS
  end

  def vote_buttons
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("[data-testid='bill-ballot'] button"))
        .filter(button => /Support this legislation|Oppose this legislation/.test(button.textContent))
        .map(button => {
          const box = button.getBoundingClientRect();
          const description = button.querySelector("span > span:last-child");
          const range = document.createRange();
          range.selectNodeContents(description);
          const text = range.getBoundingClientRect();
          return { disabled: button.disabled, width: box.width, height: box.height, left: box.left, right: box.right, top: box.top, bottom: box.bottom,
            textLeft: text.left, textRight: text.right, textTop: text.top, textBottom: text.bottom };
        });
    JS
  end

  it "seats both choices under the title, inside the first screen, at phone and desktop widths" do
    sign_in_as(user)

    [[390, 844], [1440, 900]].each do |w, h|
      width = Integer(w)
      height = Integer(h)
      with_narrow_viewport(width: width, height: height) do
        visit_narrow bill_path(bill), width: width
        expect(page).to have_css("[data-testid='bill-ballot'] button", count: 2, wait: 10)

        edges = landmarks
        expect(edges["title"]).to be_present, "the bill title was not rendered at #{width}px"
        expect(edges["ballot"]).to be_present, "the ballot was not rendered at #{width}px"
        expect(edges["score"]).to be_present, "the score panel was not rendered at #{width}px"

        expect(edges["ballot"]["top"]).to be >= edges["title"]["bottom"],
          "the ballot starts at #{edges["ballot"]["top"]}px, above the title's bottom edge " \
          "at #{edges["title"]["bottom"]}px"
        expect(edges["ballot"]["bottom"]).to be <= edges["score"]["top"],
          "the ballot reaches #{edges["ballot"]["bottom"]}px, past the top of the score panel " \
          "at #{edges["score"]["top"]}px"

        vote_buttons.each do |box|
          expect(box["bottom"]).to be <= edges["viewportHeight"],
            "a vote button reaches #{box["bottom"]}px, below the #{edges["viewportHeight"]}px " \
            "first screen at #{width}px"
        end
      end
    end
  end

  it "lays the two choices side by side on a phone and only stacks them at the narrowest viewport" do
    sign_in_as(user)

    [390, 1440].each do |width|
      with_narrow_viewport(width: width, height: 1600) do
        visit_narrow bill_path(bill), width: width
        expect(page).to have_css("[data-testid='bill-ballot'] button", count: 2, wait: 10)

        for_box, against_box = vote_buttons
        expect(against_box["left"]).to be >= for_box["right"],
          "at #{width}px Against starts at #{against_box["left"]}px, inside the For button " \
          "that reaches #{for_box["right"]}px"
        expect(against_box["top"]).to eq(for_box["top"])
      end
    end

    with_narrow_viewport do
      visit_narrow bill_path(bill)
      expect(page).to have_css("[data-testid='bill-ballot'] button", count: 2, wait: 10)

      for_box, against_box = vote_buttons
      expect(against_box["top"]).to be >= for_box["bottom"],
        "at 320px Against starts at #{against_box["top"]}px, beside the For button " \
        "that reaches #{for_box["bottom"]}px"
      expect(against_box["left"]).to eq(for_box["left"])
    end
  end

  # @lat: [[user-vote-submission#Themed web vote controls]]
  it "keeps vote descriptions inside usable buttons at phone and desktop widths" do
    sign_in_as(user)

    [390, 1440].each do |width|
      with_narrow_viewport(width: width, height: 1600) do
        visit_narrow bill_path(bill), width: width
        expect(page).to have_css("[data-testid='bill-ballot'] button", count: 2, wait: 10)

        bounds = vote_buttons
        expect(bounds.length).to eq(2)
        bounds.each do |box|
          expect(box["disabled"]).to be(false)
          expect(box["width"]).to be >= 44
          expect(box["height"]).to be >= 44
          expect(box["textLeft"]).to be >= box["left"]
          expect(box["textRight"]).to be <= box["right"]
          expect(box["textTop"]).to be >= box["top"]
          expect(box["textBottom"]).to be <= box["bottom"]
        end
      end
    end
  end
end
