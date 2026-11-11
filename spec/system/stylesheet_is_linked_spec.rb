# frozen_string_literal: true

require "rails_helper"

# @lat: [[shared-stylesheet-entrypoint#Why an import inside a JavaScript entrypoint is not enough]]
RSpec.describe "The application stylesheet reaches the browser", type: :system, js: true do
  # @lat: [[shared-stylesheet-entrypoint#Why a stylesheet entrypoint cannot regress the same way]]
  it "loads a stylesheet whose rules actually apply" do
    visit "/"

    linked = page.evaluate_script(<<~JS)
      Array.from(document.styleSheets)
           .map((sheet) => sheet.href)
           .filter((href) => href !== null).length
    JS
    expect(linked).to be_positive

    # @lat: [[shared-stylesheet-entrypoint#Why the regression guard counts CSS rules recursively]]
    rule_count = page.evaluate_script(<<~JS)
      (() => {
        let total = 0
        const walk = (rules) => {
          for (const r of rules) {
            total += 1
            if (r.cssRules) walk(r.cssRules)
          }
        }
        for (const sheet of Array.from(document.styleSheets)) {
          try { walk(sheet.cssRules) } catch (e) {}
        }
        return total
      })()
    JS
    expect(rule_count).to be > 500
  end

  # The failure's own signature: with no stylesheet, every Tailwind class in the
  # markup resolves to nothing and the browser falls back to its default serif.
  it "does not fall back to the browser's default serif on the body" do
    visit "/"

    font_family = page.evaluate_script("getComputedStyle(document.body).fontFamily")

    expect(font_family).to be_present
    expect(font_family).not_to match(/\A["']?Times/i)
  end
end
