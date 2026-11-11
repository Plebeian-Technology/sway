# frozen_string_literal: true

require "rails_helper"

# @lat: [[legislation-pipeline#Official source-link verification across jurisdictions]]
RSpec.describe "Official bill source links cross-locale contract", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:baltimore_locale) { create(:sway_locale, :baltimore) }
  let(:maryland_locale) { create(:sway_locale, :maryland) }
  let(:congress_locale) { create(:sway_locale, :congress) }

  let(:baltimore_legislator) { create(:legislator, sway_locale: baltimore_locale) }
  let(:maryland_legislator) { create(:legislator, sway_locale: maryland_locale) }
  let(:congress_legislator) { create(:legislator, sway_locale: congress_locale) }

  def extract_reader_link(response)
    if response.headers["X-Inertia"]
      JSON.parse(response.body).dig("props", "bill", "link")
    elsif (script_match = response.body.match(%r{<script\b[^>]*data-page="app"[^>]*>(.*?)</script>}m))
      raw = script_match[1].strip
      page_data = JSON.parse(raw.include?("&quot;") ? CGI.unescapeHTML(raw) : raw)
      page_data.dig("props", "bill", "link")
    elsif (div_match = response.body.match(/data-page="([^"]+)"/))
      page_data = JSON.parse(CGI.unescapeHTML(div_match[1]))
      page_data.dig("props", "bill", "link")
    end
  end

  def decoded_query(uri)
    URI.decode_www_form(uri.query.to_s).group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
  end

  describe "Baltimore City source link contract" do
    let(:legistar_detail_url) do
      "https://baltimore.legistar.com/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570"
    end
    let(:generic_search_url) do
      "https://baltimore.legistar.com/LegislationSearch.aspx"
    end
    let(:baltimore_fixture_path) do
      Rails.root.join("spec", "fixtures", "legislation", "baltimore", "legistar_detail_26_0217.html")
    end

    it "renders the authentic Legistar detail URL in bill page Inertia props and reader href, never the search URL" do
      bill = create(
        :bill,
        sway_locale: baltimore_locale,
        legislator: baltimore_legislator,
        external_id: "26-0217",
        title: "Data Centers Moratorium",
        link: legistar_detail_url
      )

      get bill_path(bill)

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component("Bill")
      bill_prop = inertia.props[:bill] || inertia.props["bill"]
      link_val = bill_prop.is_a?(Hash) ? (bill_prop[:link] || bill_prop["link"]) : nil
      expect(link_val).to eq(legistar_detail_url)
      expect(link_val).not_to include("LegislationSearch.aspx")
      expect(extract_reader_link(response)).to eq(legistar_detail_url)
    end

    it "renders nil in Inertia props and reader href when a Baltimore bill has no resolvable source link" do
      bill = create(
        :bill,
        sway_locale: baltimore_locale,
        legislator: baltimore_legislator,
        external_id: "26-9999",
        title: "Unresolvable Bill",
        link: nil
      )

      get bill_path(bill)

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component("Bill")
      bill_prop = inertia.props[:bill] || inertia.props["bill"]
      link_val = bill_prop.is_a?(Hash) ? (bill_prop[:link] || bill_prop["link"]) : nil
      expect(link_val).to be_nil
      expect(extract_reader_link(response)).to be_nil
    end

    it "verifies bill identity against the recorded Baltimore Legistar detail fixture, proving identity beyond HTTP status" do
      html = baltimore_fixture_path.read

      expect(html).to include("26-0217")
      expect(html).to include("Data Centers Moratorium")
      expect(html).to include("8135417")
      expect(html).to include("44D47DEC-EC78-4AD0-86B9-B02879001570")

      uri = URI.parse(legistar_detail_url)
      params = decoded_query(uri)
      expect(params["ID"]).to eq(["8135417"])
      expect(params["GUID"]).to eq(["44D47DEC-EC78-4AD0-86B9-B02879001570"])
    end

    it "fails verification when a same-host Legistar URL names a different bill or generic search" do
      different_bill_url = "https://baltimore.legistar.com/LegislationDetail.aspx?ID=8135418&GUID=99E99E99-1234-5678-90AB-CDEF12345678"
      html = baltimore_fixture_path.read

      diff_uri = URI.parse(different_bill_url)
      diff_params = decoded_query(diff_uri)
      expect(html).not_to include(diff_params["ID"].first.to_s)
      expect(html).not_to include(diff_params["GUID"].first.to_s)
      expect(different_bill_url).not_to eq(legistar_detail_url)
      expect(generic_search_url).not_to eq(legistar_detail_url)
    end
  end

  describe "State of Maryland source link contract" do
    let(:mga_detail_url) do
      "https://mgaleg.maryland.gov/mgawebsite/Legislation/Details/sb0001?ys=2026RS"
    end
    let(:generic_portal_root) { "https://mgaleg.maryland.gov/mgawebsite" }
    let(:generic_domain_root) { "https://mgaleg.maryland.gov" }
    let(:maryland_fixture_path) do
      Rails.root.join("spec", "fixtures", "legislation", "maryland", "mga_details_sb0001.html")
    end

    it "renders the specific MGA legislation detail URL in Inertia props and reader href, never generic portal roots" do
      bill = create(
        :bill,
        sway_locale: maryland_locale,
        legislator: maryland_legislator,
        external_id: "SB0001",
        title: "Face Coverings and Identification",
        link: mga_detail_url
      )

      get bill_path(bill)

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component("Bill")
      bill_prop = inertia.props[:bill] || inertia.props["bill"]
      link_val = bill_prop.is_a?(Hash) ? (bill_prop[:link] || bill_prop["link"]) : nil
      expect(link_val).to eq(mga_detail_url)
      expect(link_val).not_to eq(generic_portal_root)
      expect(link_val).not_to eq(generic_domain_root)
      expect(extract_reader_link(response)).to eq(mga_detail_url)
    end

    it "verifies bill identity against the recorded MGA detail fixture, proving identity beyond HTTP status" do
      html = maryland_fixture_path.read

      expect(html).to include("SB0001")
      expect(html).to include("Face Coverings and Identification")
      expect(html).to include("/2026RS/bills/sb/sb0001f.pdf")

      uri = URI.parse(mga_detail_url)
      expect(uri.path).to eq("/mgawebsite/Legislation/Details/sb0001")
      expect(decoded_query(uri)["ys"]).to eq(["2026RS"])
    end

    it "fails verification when a same-host MGA URL names a different valid bill or session" do
      different_bill_url = "https://mgaleg.maryland.gov/mgawebsite/Legislation/Details/sb0002?ys=2026RS"
      different_session_url = "https://mgaleg.maryland.gov/mgawebsite/Legislation/Details/sb0001?ys=2025RS"
      html = maryland_fixture_path.read

      expect(html).not_to include("SB0002")
      expect(html).not_to include("/2025RS/")
      expect(different_bill_url).not_to eq(mga_detail_url)
      expect(different_session_url).not_to eq(mga_detail_url)
    end
  end

  describe "US Congress source link contract" do
    let(:congress_detail_url) do
      "https://www.congress.gov/bill/118th-congress/house-bill/1"
    end
    let(:generic_congress_domain) { "https://congress.gov" }
    let(:generic_www_congress_domain) { "https://www.congress.gov" }
    let(:congress_fixture_path) do
      Rails.root.join("spec", "fixtures", "legislation", "congress", "bill_detail_118_hr_1.json")
    end

    it "renders the specific Congress.gov bill detail URL in Inertia props and reader href, never generic domain roots" do
      bill = create(
        :bill,
        sway_locale: congress_locale,
        legislator: congress_legislator,
        external_id: "118-hr-1",
        title: "For the People Act of 2023",
        link: congress_detail_url
      )

      get bill_path(bill)

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component("Bill")
      bill_prop = inertia.props[:bill] || inertia.props["bill"]
      link_val = bill_prop.is_a?(Hash) ? (bill_prop[:link] || bill_prop["link"]) : nil
      expect(link_val).to eq(congress_detail_url)
      expect(link_val).not_to eq(generic_congress_domain)
      expect(link_val).not_to eq(generic_www_congress_domain)
      expect(extract_reader_link(response)).to eq(congress_detail_url)
    end

    it "verifies bill identity against the recorded Congress.gov detail fixture, proving identity beyond HTTP status" do
      json_data = JSON.parse(congress_fixture_path.read)
      bill_data = json_data["bill"]

      expect(bill_data["congress"]).to eq(118)
      expect(bill_data["type"]).to eq("HR")
      expect(bill_data["number"]).to eq("1")
      expect(bill_data["title"]).to eq("For the People Act of 2023")

      expected_path = "/bill/#{bill_data["congress"]}th-congress/house-bill/#{bill_data["number"]}"
      uri = URI.parse(congress_detail_url)
      expect(uri.path).to eq(expected_path)
    end

    it "fails verification when a same-host Congress URL names a different valid bill (e.g. HR 8035 instead of HR 1)" do
      mismatched_url = "https://www.congress.gov/bill/118th-congress/house-bill/8035"
      json_data = JSON.parse(congress_fixture_path.read)
      bill_data = json_data["bill"]

      uri = URI.parse(mismatched_url)
      expect(uri.path).not_to eq("/bill/#{bill_data["congress"]}th-congress/house-bill/#{bill_data["number"]}")
      expect(mismatched_url).not_to eq(congress_detail_url)
    end
  end

  describe "Cross-locale link uniqueness and nullability invariants" do
    it "enforces uniqueness for non-nil links across different locales" do
      shared_link = "https://example.gov/unique-legislation-link-101"

      create(
        :bill,
        sway_locale: baltimore_locale,
        legislator: baltimore_legislator,
        external_id: "B-101",
        link: shared_link
      )

      cross_locale_duplicate = build(
        :bill,
        sway_locale: maryland_locale,
        legislator: maryland_legislator,
        external_id: "MD-101",
        link: shared_link
      )

      expect(cross_locale_duplicate).not_to be_valid
      expect(cross_locale_duplicate.errors[:link]).to be_present
    end

    it "allows multiple bills across multiple locales to concurrently hold link: nil" do
      b_nil = create(
        :bill,
        sway_locale: baltimore_locale,
        legislator: baltimore_legislator,
        external_id: "B-NIL",
        link: nil
      )
      md_nil = create(
        :bill,
        sway_locale: maryland_locale,
        legislator: maryland_legislator,
        external_id: "MD-NIL",
        link: nil
      )
      c_nil = create(
        :bill,
        sway_locale: congress_locale,
        legislator: congress_legislator,
        external_id: "C-NIL",
        link: nil
      )

      expect(b_nil.reload.link).to be_nil
      expect(md_nil.reload.link).to be_nil
      expect(c_nil.reload.link).to be_nil
    end

    it "normalizes whitespace links to nil before validation across all locales" do
      bill = build(
        :bill,
        sway_locale: maryland_locale,
        legislator: maryland_legislator,
        external_id: "MD-BLANK",
        link: "   \t  \n "
      )

      expect(bill).to be_valid
      bill.save!
      expect(bill.reload.link).to be_nil
    end
  end

  describe "SummaryCitationValidator official link recognition" do
    it "treats genuine detail links as official and rejects generic search links across supported SwayLocales" do
      valid_baltimore = build(
        :bill,
        link: "https://baltimore.legistar.com/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570"
      )
      search_baltimore = build(
        :bill,
        link: "https://baltimore.legistar.com/LegislationSearch.aspx"
      )
      valid_maryland = build(
        :bill,
        link: "https://mgaleg.maryland.gov/mgawebsite/Legislation/Details/sb0001?ys=2026RS"
      )
      valid_congress = build(
        :bill,
        link: "https://www.congress.gov/bill/118th-congress/house-bill/1"
      )

      expect(SummaryCitationValidator.official_bill_url(valid_baltimore)).to be_present
      expect(SummaryCitationValidator.official_bill_url(search_baltimore)).to be_nil
      expect(SummaryCitationValidator.official_bill_url(valid_maryland)).to be_present
      expect(SummaryCitationValidator.official_bill_url(valid_congress)).to be_present
    end
  end
end
