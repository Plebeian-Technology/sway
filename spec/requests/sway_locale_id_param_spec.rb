# frozen_string_literal: true

require "rails_helper"

# @lat: [[sway-locale-id-param-cookie-guard#Why SwayLocalesController.show never writes the cookie either]]
RSpec.describe "the sway_locale_id parameter", type: :request do
  let!(:baltimore) do
    create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states")
  end

  # An id no row holds. The check is what makes that true rather than assumed:
  # if a locale ever really has this id, these examples would quietly start
  # testing the opposite of what they say, so they stop instead.
  let(:missing_locale_id) do
    id = 2_000_000_000
    raise "a SwayLocale really holds id #{id}; pick another" if SwayLocale.exists?(id: id)
    id
  end

  def locale_cookie
    cookies[:sway_locale_id]
  end

  describe "an id that names no jurisdiction" do
    it "does not write it to the cookie" do
      get "/", params: {sway_locale_id: missing_locale_id}

      expect(locale_cookie).to be_blank
    end

    it "still renders, rather than answering with an error page" do
      get "/", params: {sway_locale_id: missing_locale_id}

      expect(response).to have_http_status(:ok)
    end

    it "tells the reader, instead of quietly showing another jurisdiction" do
      get "/", params: {sway_locale_id: missing_locale_id}

      expect(flash[:alert]).to include("could not be found")
    end

    # The whole failure was invisible because the fall-through is silent. A
    # value that is not a number at all took the same path: `.to_i` turned
    # "haystack" into 0 and wrote that.
    it "refuses a value that is not an id at all" do
      get "/", params: {sway_locale_id: "haystack"}

      expect(locale_cookie).to be_blank
      expect(response).to have_http_status(:ok)
    end
  end

  describe "an id that names a real jurisdiction" do
    it "is written to the cookie, as before" do
      get "/", params: {sway_locale_id: baltimore.id}

      expect(locale_cookie).to eq(baltimore.id.to_s)
    end
  end

  describe "a cookie left holding an id that no longer names anything" do
    # The repair path for browsers poisoned before the guard above existed.
    # Without it their readers stay on the default for as long as the cookie
    # lasts, and nothing prompts them to pick again.
    it "is cleared, so it stops being consulted on every later request" do
      cookies[:sway_locale_id] = missing_locale_id.to_s

      get "/"

      expect(locale_cookie).to be_blank
    end

    it "leaves a cookie naming a real jurisdiction alone" do
      cookies[:sway_locale_id] = baltimore.id.to_s

      get "/"

      expect(locale_cookie).to eq(baltimore.id.to_s)
    end
  end
end
