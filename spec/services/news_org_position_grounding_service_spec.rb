# frozen_string_literal: true

require "rails_helper"

RSpec.describe NewsOrgPositionGroundingService do
  let(:sway_locale) { create(:sway_locale) }
  let(:other_locale) { create(:sway_locale) }
  let(:bill) { create(:bill, sway_locale: sway_locale) }
  let(:user) { create(:user) }

  describe ".eligible_reporting_articles and .reporting_eligible?" do
    it "returns approved reporting articles with usable text" do
      article = create(:news_article, article_kind: "reporting")
      bna = create(
        :bill_news_article,
        bill: bill,
        news_article: article,
        approved: true,
        approved_by: user,
        approved_at: Time.current
      )
      text_version = create(
        :news_article_text_version,
        news_article: article,
        extraction_status: "extracted",
        text: "Reporting article text about the bill."
      )
      bna.update_columns(current_text_version_id: text_version.id)

      eligible = described_class.eligible_reporting_articles(bill)
      expect(eligible).to include(bna)
      expect(described_class.reporting_eligible?(bill)).to be(true)
    end

    it "excludes unapproved articles" do
      article = create(:news_article, article_kind: "reporting")
      bna = create(
        :bill_news_article,
        bill: bill,
        news_article: article,
        approved: false
      )
      text_version = create(
        :news_article_text_version,
        news_article: article,
        extraction_status: "extracted",
        text: "Unapproved article text."
      )
      bna.update_columns(current_text_version_id: text_version.id)

      expect(described_class.eligible_reporting_articles(bill)).not_to include(bna)
      expect(described_class.reporting_eligible?(bill)).to be(false)
    end

    it "excludes op_ed and editorial articles from reporting eligibility" do
      op_ed_article = create(:news_article, article_kind: "op_ed")
      bna = create(
        :bill_news_article,
        bill: bill,
        news_article: op_ed_article,
        approved: true,
        approved_by: user
      )
      text_version = create(
        :news_article_text_version,
        news_article: op_ed_article,
        extraction_status: "extracted",
        text: "Opinion piece text."
      )
      bna.update_columns(current_text_version_id: text_version.id)

      expect(described_class.eligible_reporting_articles(bill)).not_to include(bna)
      expect(described_class.reporting_eligible?(bill)).to be(false)
    end

    it "excludes articles with failed or paywalled text versions" do
      article = create(:news_article, article_kind: "reporting")
      bna = create(
        :bill_news_article,
        bill: bill,
        news_article: article,
        approved: true,
        approved_by: user
      )
      text_version = create(
        :news_article_text_version,
        news_article: article,
        extraction_status: "paywalled",
        text: nil
      )
      bna.update_columns(current_text_version_id: text_version.id)

      expect(described_class.eligible_reporting_articles(bill)).not_to include(bna)
      expect(described_class.reporting_eligible?(bill)).to be(false)
    end

    it "excludes articles associated with a different bill" do
      other_bill = create(:bill, sway_locale: sway_locale)
      article = create(:news_article, article_kind: "reporting")
      bna = create(
        :bill_news_article,
        bill: other_bill,
        news_article: article,
        approved: true,
        approved_by: user
      )
      text_version = create(
        :news_article_text_version,
        news_article: article,
        extraction_status: "extracted",
        text: "Other bill text."
      )
      bna.update_columns(current_text_version_id: text_version.id)

      expect(described_class.eligible_reporting_articles(bill)).not_to include(bna)
      expect(described_class.reporting_eligible?(bill)).to be(false)
    end

    it "returns none and false when bill is nil" do
      expect(described_class.eligible_reporting_articles(nil)).to be_empty
      expect(described_class.reporting_eligible?(nil)).to be(false)
    end
  end

  describe ".normalize_organization_name" do
    it "strips leading 'the' case-insensitively" do
      expect(described_class.normalize_organization_name("The ACLU of Maryland")).to eq("aclu of maryland")
      expect(described_class.normalize_organization_name("the Greater Baltimore Committee")).to eq("greater baltimore committee")
    end

    it "strips corporate suffixes" do
      expect(described_class.normalize_organization_name("Acme Advocates, Inc.")).to eq("acme advocates")
      expect(described_class.normalize_organization_name("Civic Alliance LLC")).to eq("civic alliance")
      expect(described_class.normalize_organization_name("Housing Coalition Corp.")).to eq("housing coalition")
      expect(described_class.normalize_organization_name("Public Works Co.")).to eq("public works")
      expect(described_class.normalize_organization_name("Action Group Ltd")).to eq("action group")
    end

    it "removes punctuation and collapses whitespace" do
      expect(described_class.normalize_organization_name("CASA -- Maryland, Inc.")).to eq("casa maryland")
      expect(described_class.normalize_organization_name("  Fair   Development   Coalition  ")).to eq("fair development coalition")
    end

    it "returns an empty string for blank or nil input" do
      expect(described_class.normalize_organization_name(nil)).to eq("")
      expect(described_class.normalize_organization_name("   ")).to eq("")
    end
  end

  describe ".match_existing_organization" do
    it "matches exactly by normalized name" do
      existing_org = create(:organization, sway_locale: sway_locale, name: "Maryland Food Bank")
      matched = described_class.match_existing_organization(bill, "The Maryland Food Bank, Inc.")
      expect(matched).to eq(existing_org)
    end

    it "matches fuzzily when Jaro-Winkler distance is >= 0.9" do
      existing_org = create(:organization, sway_locale: sway_locale, name: "Maryland Food Bank")
      matched = described_class.match_existing_organization(bill, "Maryland Food Banks")
      expect(matched).to eq(existing_org)
    end

    it "does not match when similarity is below 0.9" do
      create(:organization, sway_locale: sway_locale, name: "Maryland Food Bank")
      matched = described_class.match_existing_organization(bill, "Maryland Bank Union")
      expect(matched).to be_nil
    end

    it "scopes matching strictly to bill sway_locale" do
      existing_org = create(:organization, sway_locale: sway_locale, name: "Maryland Food Bank")
      other_locale_org = create(:organization, sway_locale: other_locale, name: "Maryland Food Bank")
      other_bill = create(:bill, sway_locale: other_locale)
      matched = described_class.match_existing_organization(other_bill, "Maryland Food Bank")
      expect(matched).to eq(other_locale_org)
      expect(matched).not_to eq(existing_org)
    end

    it "returns nil when bill is nil or org_name is blank" do
      expect(described_class.match_existing_organization(nil, "Maryland Food Bank")).to be_nil
      expect(described_class.match_existing_organization(bill, "")).to be_nil
      expect(described_class.match_existing_organization(bill, nil)).to be_nil
    end
  end

  describe ".organization_has_users?" do
    let(:org) { create(:organization, sway_locale: sway_locale) }

    it "returns true when UserOrganizationMembership exists" do
      create(:user_organization_membership, organization: org, user: user)
      expect(described_class.organization_has_users?(org)).to be(true)
    end

    it "returns false when no UserOrganizationMembership exists" do
      expect(described_class.organization_has_users?(org)).to be(false)
    end

    it "returns false when organization is nil" do
      expect(described_class.organization_has_users?(nil)).to be(false)
    end
  end

  describe ".public_body_name?" do
    it "returns true for governmental and municipal public bodies" do
      expect(described_class.public_body_name?("Department of Housing and Community Development")).to be(true)
      expect(described_class.public_body_name?("Baltimore City Council")).to be(true)
      expect(described_class.public_body_name?("Board of Estimates")).to be(true)
      expect(described_class.public_body_name?("Mayor's Office of Homeless Services")).to be(true)
      expect(described_class.public_body_name?("Maryland State Department of Education")).to be(true)
      expect(described_class.public_body_name?("Office of the Public Defender")).to be(true)
      expect(described_class.public_body_name?("City of Baltimore")).to be(true)
      expect(described_class.public_body_name?("County of Anne Arundel")).to be(true)
      expect(described_class.public_body_name?("Board of Elections")).to be(true)
    end

    it "returns false for civic, labor, advocacy, and business organizations" do
      expect(described_class.public_body_name?("ACLU of Maryland")).to be(false)
      expect(described_class.public_body_name?("CASA de Maryland")).to be(false)
      expect(described_class.public_body_name?("Maryland Food Bank")).to be(false)
      expect(described_class.public_body_name?("Greater Baltimore Committee")).to be(false)
      expect(described_class.public_body_name?("Clean Water Action")).to be(false)
      expect(described_class.public_body_name?("Teachers Association of Baltimore County")).to be(false)
    end

    it "returns false for nil and blank" do
      expect(described_class.public_body_name?(nil)).to be(false)
      expect(described_class.public_body_name?("")).to be(false)
    end
  end

  describe ".filter_draft_positions" do
    let(:news_article) do
      create(
        :news_article,
        article_kind: "reporting",
        outlet_name: "The Baltimore Banner",
        canonical_url: "https://thebaltimorebanner.com/community/fair-housing-bill",
        title: "City Council debates fair housing legislation",
        author_name: "Jane Journalist"
      )
    end
    let(:article_text) do
      "The City Council heard debate on the fair housing measure on Monday.\n\n" \
      "Advocacy groups rallied outside City Hall before the session opened.\n\n" \
      "\"We strongly support this legislation to safeguard fair housing for all tenants,\" " \
      "said Jane Doe, Executive Director of ACLU of Maryland. \"It is a vital step forward.\"\n\n" \
      "Opponents also voiced concerns about the implementation costs.\n\n" \
      "\"This mandate will overburden small property owners across Baltimore,\" " \
      "said John Smith, President of Greater Baltimore Housing Providers.\n\n" \
      "A volunteer at Baltimore Tenants Coalition said the bill was good."
    end
    let(:text_version) do
      create(
        :news_article_text_version,
        news_article: news_article,
        extraction_status: "extracted",
        text: article_text
      )
    end
    let(:bna) do
      b = create(
        :bill_news_article,
        bill: bill,
        news_article: news_article,
        approved: true,
        approved_by: user,
        approved_at: Time.current
      )
      b.update_columns(current_text_version_id: text_version.id)
      b
    end

    context "when hearing_testimony_present is true" do
      it "keeps hearing-sourced drafts and news-sourced drafts together" do
        hearing_draft = {
          "org_name" => "Maryland Food Bank",
          "stance" => "support",
          "summary" => "Testified in favor at the hearing."
        }
        valid_news_draft = {
          "org_name" => "ACLU of Maryland",
          "stance" => "support",
          "summary" => "Supports tenant fair housing rights.",
          "bill_news_article_id" => bna.id,
          "text_version_id" => text_version.id,
          "evidence_excerpt" => "We strongly support this legislation to safeguard fair housing for all tenants",
          "speaker_name" => "Jane Doe",
          "speaker_role" => "Executive Director"
        }
        raw = [hearing_draft, valid_news_draft]
        results = described_class.filter_draft_positions(
          bill: bill,
          raw_positions: raw,
          hearing_testimony_present: true
        )

        expect(results.size).to eq(2)
        expect(results.pluck("org_name")).to contain_exactly("Maryland Food Bank", "ACLU of Maryland")
      end

      it "drops hearing drafts if the matched organization has user memberships" do
        org = create(:organization, sway_locale: sway_locale, name: "Maryland Food Bank")
        create(:user_organization_membership, organization: org, user: user)

        hearing_draft = {
          "org_name" => "Maryland Food Bank",
          "stance" => "support",
          "summary" => "Testified in favor at the hearing."
        }
        valid_news_draft = {
          "org_name" => "ACLU of Maryland",
          "stance" => "support",
          "summary" => "Supports tenant fair housing rights.",
          "bill_news_article_id" => bna.id,
          "text_version_id" => text_version.id,
          "evidence_excerpt" => "We strongly support this legislation to safeguard fair housing for all tenants",
          "speaker_name" => "Jane Doe",
          "speaker_role" => "Executive Director"
        }
        raw = [hearing_draft, valid_news_draft]
        results = described_class.filter_draft_positions(
          bill: bill,
          raw_positions: raw,
          hearing_testimony_present: true
        )

        expect(results.size).to eq(1)
        expect(results.first["org_name"]).to eq("ACLU of Maryland")
      end

      it "canonicalizes hearing draft org_name to existing organization name" do
        create(:organization, sway_locale: sway_locale, name: "Maryland Food Bank, Inc.")
        hearing_draft = {
          "org_name" => "Maryland Food Bank",
          "stance" => "support",
          "summary" => "Testified in favor at the hearing."
        }
        raw = [hearing_draft]
        results = described_class.filter_draft_positions(
          bill: bill,
          raw_positions: raw,
          hearing_testimony_present: true
        )

        expect(results.first["org_name"]).to eq("Maryland Food Bank, Inc.")
      end
    end

    context "when hearing_testimony_present is false" do
      it "drops hearing-sourced drafts and keeps valid news drafts" do
        hearing_draft = {
          "org_name" => "Maryland Food Bank",
          "stance" => "support",
          "summary" => "Testified in favor at the hearing."
        }
        valid_news_draft = {
          "org_name" => "ACLU of Maryland",
          "stance" => "support",
          "summary" => "Supports tenant fair housing rights.",
          "bill_news_article_id" => bna.id,
          "text_version_id" => text_version.id,
          "evidence_excerpt" => "We strongly support this legislation to safeguard fair housing for all tenants",
          "speaker_name" => "Jane Doe",
          "speaker_role" => "Executive Director"
        }
        raw = [hearing_draft, valid_news_draft]
        results = described_class.filter_draft_positions(
          bill: bill,
          raw_positions: raw,
          hearing_testimony_present: false
        )

        expect(results.size).to eq(1)
        expect(results.first["org_name"]).to eq("ACLU of Maryland")
      end
    end

    context "news draft validation and enrichment" do
      it "enriches valid news drafts with metadata, offsets, paragraphs, and formatted summary" do
        valid_news_draft = {
          "org_name" => "ACLU of Maryland",
          "stance" => "support",
          "summary" => "Supports tenant fair housing rights.",
          "bill_news_article_id" => bna.id,
          "text_version_id" => text_version.id,
          "evidence_excerpt" => "We strongly support this legislation to safeguard fair housing for all tenants",
          "speaker_name" => "Jane Doe",
          "speaker_role" => "Executive Director"
        }
        results = described_class.filter_draft_positions(
          bill: bill,
          raw_positions: [valid_news_draft],
          hearing_testimony_present: false
        )

        expect(results.size).to eq(1)
        res = results.first
        expect(res["source_url"]).to eq("https://thebaltimorebanner.com/community/fair-housing-bill")
        expect(res["outlet_name"]).to eq("The Baltimore Banner")
        expect(res["article_title"]).to eq("City Council debates fair housing legislation")
        expect(res["excerpt_offset"]).to eq(article_text.index(valid_news_draft["evidence_excerpt"]))
        expect(res["excerpt_length"]).to eq(valid_news_draft["evidence_excerpt"].length)
        expect(res["excerpt_paragraph"]).to eq(3)
        expect(res["summary"]).to include("\"We strongly support this legislation to safeguard fair housing for all tenants\"")
        expect(res["summary"]).to include("Jane Doe, Executive Director in The Baltimore Banner (Support).")
        expect(res["summary"]).to include("https://thebaltimorebanner.com/community/fair-housing-bill")
      end

      it "drops news drafts whose excerpt does not appear verbatim in article text" do
        draft = {
          "org_name" => "ACLU of Maryland",
          "stance" => "support",
          "summary" => "Supports tenant fair housing rights.",
          "bill_news_article_id" => bna.id,
          "text_version_id" => text_version.id,
          "evidence_excerpt" => "We completely oppose this non-existent text",
          "speaker_name" => "Jane Doe",
          "speaker_role" => "Executive Director"
        }
        results = described_class.filter_draft_positions(
          bill: bill,
          raw_positions: [draft],
          hearing_testimony_present: false
        )
        expect(results).to be_empty
      end

      it "drops news drafts lacking direct quotation marks" do
        no_quote_text = "Jane Doe Executive Director said they strongly support this legislation."
        tv = create(
          :news_article_text_version,
          news_article: news_article,
          extraction_status: "extracted",
          text: no_quote_text
        )
        bna.update_columns(current_text_version_id: tv.id)

        draft = {
          "org_name" => "ACLU of Maryland",
          "stance" => "support",
          "summary" => "Supports tenant fair housing rights.",
          "bill_news_article_id" => bna.id,
          "text_version_id" => tv.id,
          "evidence_excerpt" => "strongly support this legislation",
          "speaker_name" => "Jane Doe",
          "speaker_role" => "Executive Director"
        }
        results = described_class.filter_draft_positions(
          bill: bill,
          raw_positions: [draft],
          hearing_testimony_present: false
        )
        expect(results).to be_empty
      end

      it "rejects unquoted paraphrases containing multiple apostrophes or contractions" do
        contraction_text = "Jane Doe, Executive Director of ACLU of Maryland, said the union's members don't support this bill."
        tv = create(
          :news_article_text_version,
          news_article: news_article,
          extraction_status: "extracted",
          text: contraction_text
        )
        bna.update_columns(current_text_version_id: tv.id)

        draft = {
          "org_name" => "ACLU of Maryland",
          "stance" => "oppose",
          "summary" => "Opposes the bill.",
          "bill_news_article_id" => bna.id,
          "text_version_id" => tv.id,
          "evidence_excerpt" => "The union's members don't support this bill".downcase,
          "speaker_name" => "Jane Doe",
          "speaker_role" => "Executive Director"
        }
        results = described_class.filter_draft_positions(
          bill: bill,
          raw_positions: [draft],
          hearing_testimony_present: false
        )
        expect(results).to be_empty
      end

      it "rejects an unquoted paraphrase adjacent to an unrelated quote in the window while accepting an excerpt inside quotation marks" do
        adjacent_text = "\"Yes we are here,\" said a bystander. Jane Doe, Executive Director of ACLU of Maryland, opposes the measure."
        tv = create(
          :news_article_text_version,
          news_article: news_article,
          extraction_status: "extracted",
          text: adjacent_text
        )
        bna.update_columns(current_text_version_id: tv.id)

        paraphrase_draft = {
          "org_name" => "ACLU of Maryland",
          "stance" => "oppose",
          "summary" => "Opposes the measure.",
          "bill_news_article_id" => bna.id,
          "text_version_id" => tv.id,
          "evidence_excerpt" => "Jane Doe, Executive Director of ACLU of Maryland, opposes the measure",
          "speaker_name" => "Jane Doe",
          "speaker_role" => "Executive Director"
        }
        results = described_class.filter_draft_positions(
          bill: bill,
          raw_positions: [paraphrase_draft],
          hearing_testimony_present: false
        )
        expect(results).to be_empty

        quoted_text = "\"We strongly oppose this harmful measure,\" said Jane Doe, Executive Director of ACLU of Maryland."
        tv_quoted = create(
          :news_article_text_version,
          news_article: news_article,
          extraction_status: "extracted",
          text: quoted_text
        )
        bna.update_columns(current_text_version_id: tv_quoted.id)

        omitted_quotes_draft = paraphrase_draft.merge(
          "text_version_id" => tv_quoted.id,
          "evidence_excerpt" => "We strongly oppose this harmful measure"
        )
        accepted = described_class.filter_draft_positions(
          bill: bill,
          raw_positions: [omitted_quotes_draft],
          hearing_testimony_present: false
        )
        expect(accepted.size).to eq(1)
      end

      it "drops rank-and-file descriptions without spokesperson authority even if the LLM hallucinates an officer speaker_role" do
        volunteer_text = "\"We strongly support this legislation for tenants,\" said John Roe, a volunteer at Baltimore Tenants Coalition."
        tv = create(
          :news_article_text_version,
          news_article: news_article,
          extraction_status: "extracted",
          text: volunteer_text
        )
        bna.update_columns(current_text_version_id: tv.id)

        hallucinated_role_draft = {
          "org_name" => "Baltimore Tenants Coalition",
          "stance" => "support",
          "summary" => "Supports the bill.",
          "bill_news_article_id" => bna.id,
          "text_version_id" => tv.id,
          "evidence_excerpt" => "We strongly support this legislation for tenants",
          "speaker_name" => "John Roe",
          "speaker_role" => "Executive Director"
        }
        results = described_class.filter_draft_positions(
          bill: bill,
          raw_positions: [hallucinated_role_draft],
          hearing_testimony_present: false
        )
        expect(results).to be_empty

        both_roles_text = "\"We strongly support this legislation for tenants,\" said John Roe, a member of the task force and Executive Director of Baltimore Tenants Coalition."
        tv_both = create(
          :news_article_text_version,
          news_article: news_article,
          extraction_status: "extracted",
          text: both_roles_text
        )
        bna.update_columns(current_text_version_id: tv_both.id)

        valid_both_draft = hallucinated_role_draft.merge("text_version_id" => tv_both.id)
        accepted = described_class.filter_draft_positions(
          bill: bill,
          raw_positions: [valid_both_draft],
          hearing_testimony_present: false
        )
        expect(accepted.size).to eq(1)
      end

      it "drops rank-and-file descriptions without spokesperson authority (MERE_MEMBER_PATTERN)" do
        draft = {
          "org_name" => "Baltimore Tenants Coalition",
          "stance" => "support",
          "summary" => "Volunteer spoke in favor.",
          "bill_news_article_id" => bna.id,
          "text_version_id" => text_version.id,
          "evidence_excerpt" => "the bill was good",
          "speaker_name" => "Anonymous",
          "speaker_role" => "volunteer at Baltimore Tenants Coalition"
        }
        results = described_class.filter_draft_positions(
          bill: bill,
          raw_positions: [draft],
          hearing_testimony_present: false
        )
        expect(results).to be_empty
      end

      it "accepts institutional authority without individual speaker name" do
        official_text = "In an official statement, ACLU of Maryland said: \"This measure will ensure equitable housing for all citizens.\""
        tv = create(
          :news_article_text_version,
          news_article: news_article,
          extraction_status: "extracted",
          text: official_text
        )
        bna.update_columns(current_text_version_id: tv.id)

        draft = {
          "org_name" => "ACLU of Maryland",
          "stance" => "support",
          "summary" => "Official statement.",
          "bill_news_article_id" => bna.id,
          "text_version_id" => tv.id,
          "evidence_excerpt" => "This measure will ensure equitable housing for all citizens.",
          "speaker_name" => nil,
          "speaker_role" => "official statement"
        }
        results = described_class.filter_draft_positions(
          bill: bill,
          raw_positions: [draft],
          hearing_testimony_present: false
        )
        expect(results.size).to eq(1)
        expect(results.first["summary"]).to include("Statement from ACLU of Maryland")
      end

      it "drops public body organizations" do
        public_text = "\"We will enforce the law vigorously,\" said Jane Doe, Director of Baltimore City Council."
        tv = create(
          :news_article_text_version,
          news_article: news_article,
          extraction_status: "extracted",
          text: public_text
        )
        bna.update_columns(current_text_version_id: tv.id)

        draft = {
          "org_name" => "Baltimore City Council",
          "stance" => "support",
          "summary" => "Public body position.",
          "bill_news_article_id" => bna.id,
          "text_version_id" => tv.id,
          "evidence_excerpt" => "We will enforce the law vigorously",
          "speaker_name" => "Jane Doe",
          "speaker_role" => "Director"
        }
        results = described_class.filter_draft_positions(
          bill: bill,
          raw_positions: [draft],
          hearing_testimony_present: false
        )
        expect(results).to be_empty
      end

      it "drops self-attribution matching outlet_name or author_name" do
        base_draft = {
          "org_name" => "ACLU of Maryland",
          "stance" => "support",
          "summary" => "Supports tenant fair housing rights.",
          "bill_news_article_id" => bna.id,
          "text_version_id" => text_version.id,
          "evidence_excerpt" => "We strongly support this legislation to safeguard fair housing for all tenants",
          "speaker_name" => "Jane Doe",
          "speaker_role" => "Executive Director"
        }
        draft_outlet = base_draft.merge("org_name" => "The Baltimore Banner")
        results_outlet = described_class.filter_draft_positions(
          bill: bill,
          raw_positions: [draft_outlet],
          hearing_testimony_present: false
        )
        expect(results_outlet).to be_empty

        draft_author = base_draft.merge("org_name" => "Jane Journalist")
        results_author = described_class.filter_draft_positions(
          bill: bill,
          raw_positions: [draft_author],
          hearing_testimony_present: false
        )
        expect(results_author).to be_empty
      end

      it "drops drafts whose organization has user memberships" do
        org = create(:organization, sway_locale: sway_locale, name: "ACLU of Maryland")
        create(:user_organization_membership, organization: org, user: user)

        valid_news_draft = {
          "org_name" => "ACLU of Maryland",
          "stance" => "support",
          "summary" => "Supports tenant fair housing rights.",
          "bill_news_article_id" => bna.id,
          "text_version_id" => text_version.id,
          "evidence_excerpt" => "We strongly support this legislation to safeguard fair housing for all tenants",
          "speaker_name" => "Jane Doe",
          "speaker_role" => "Executive Director"
        }
        results = described_class.filter_draft_positions(
          bill: bill,
          raw_positions: [valid_news_draft],
          hearing_testimony_present: false
        )
        expect(results).to be_empty
      end

      it "deduplicates multiple drafts that normalize to the same organization name" do
        base_draft = {
          "stance" => "support",
          "summary" => "Supports tenant fair housing rights.",
          "bill_news_article_id" => bna.id,
          "text_version_id" => text_version.id,
          "evidence_excerpt" => "We strongly support this legislation to safeguard fair housing for all tenants",
          "speaker_name" => "Jane Doe",
          "speaker_role" => "Executive Director"
        }
        draft1 = base_draft.merge("org_name" => "ACLU of Maryland")
        draft2 = base_draft.merge("org_name" => "The ACLU of Maryland, Inc.")
        results = described_class.filter_draft_positions(
          bill: bill,
          raw_positions: [draft1, draft2],
          hearing_testimony_present: false
        )
        expect(results.size).to eq(1)
      end

      it "works with snapshots when provided" do
        snapshot = NewsArticleSourceSnapshot.new(
          bill_id: bill.id,
          source_entries: [
            {
              "bill_news_article_id" => bna.id,
              "text_version_id" => text_version.id
            }
          ]
        )

        valid_news_draft = {
          "org_name" => "ACLU of Maryland",
          "stance" => "support",
          "summary" => "Supports tenant fair housing rights.",
          "bill_news_article_id" => bna.id,
          "text_version_id" => text_version.id,
          "evidence_excerpt" => "We strongly support this legislation to safeguard fair housing for all tenants",
          "speaker_name" => "Jane Doe",
          "speaker_role" => "Executive Director"
        }
        results = described_class.filter_draft_positions(
          bill: bill,
          raw_positions: [valid_news_draft],
          snapshots: [snapshot],
          hearing_testimony_present: false
        )
        expect(results.size).to eq(1)
      end
    end
  end

  describe ".entry_still_grounded?" do
    let(:news_article) do
      create(
        :news_article,
        article_kind: "reporting",
        outlet_name: "The Baltimore Banner",
        canonical_url: "https://thebaltimorebanner.com/story",
        title: "Bill Debated"
      )
    end
    let(:article_text) do
      "\"We strongly support this legislation to safeguard fair housing for all tenants,\" " \
      "said Jane Doe, Executive Director of ACLU of Maryland."
    end
    let(:text_version) do
      create(
        :news_article_text_version,
        news_article: news_article,
        extraction_status: "extracted",
        text: article_text
      )
    end
    let(:bna) do
      b = create(
        :bill_news_article,
        bill: bill,
        news_article: news_article,
        approved: true,
        approved_by: user,
        approved_at: Time.current
      )
      b.update_columns(current_text_version_id: text_version.id)
      b
    end

    it "returns true for a fully grounded entry" do
      grounded_entry = {
        "org_name" => "ACLU of Maryland",
        "stance" => "support",
        "summary" => "Supports fair housing.",
        "bill_news_article_id" => bna.id,
        "text_version_id" => text_version.id,
        "evidence_excerpt" => "We strongly support this legislation to safeguard fair housing for all tenants",
        "speaker_name" => "Jane Doe",
        "speaker_role" => "Executive Director"
      }
      expect(described_class.entry_still_grounded?(grounded_entry, bill: bill)).to be(true)
    end

    it "tolerates nil or blank summary on neutral drafts edited via BillDraftOrgPositionsController" do
      neutral_entry = {
        "org_name" => "ACLU of Maryland",
        "stance" => "neutral",
        "summary" => nil,
        "bill_news_article_id" => bna.id,
        "text_version_id" => text_version.id,
        "evidence_excerpt" => "We strongly support this legislation to safeguard fair housing for all tenants",
        "speaker_name" => "Jane Doe",
        "speaker_role" => "Executive Director"
      }
      expect(described_class.entry_still_grounded?(neutral_entry, bill: bill)).to be(true)
    end

    it "returns false if the backing bill_news_article was unapproved" do
      grounded_entry = {
        "org_name" => "ACLU of Maryland",
        "stance" => "support",
        "summary" => "Supports fair housing.",
        "bill_news_article_id" => bna.id,
        "text_version_id" => text_version.id,
        "evidence_excerpt" => "We strongly support this legislation to safeguard fair housing for all tenants",
        "speaker_name" => "Jane Doe",
        "speaker_role" => "Executive Director"
      }
      bna.update_columns(approved: false)
      expect(described_class.entry_still_grounded?(grounded_entry, bill: bill)).to be(false)
    end

    it "returns false if the current_text_version_id on the article changed" do
      grounded_entry = {
        "org_name" => "ACLU of Maryland",
        "stance" => "support",
        "summary" => "Supports fair housing.",
        "bill_news_article_id" => bna.id,
        "text_version_id" => text_version.id,
        "evidence_excerpt" => "We strongly support this legislation to safeguard fair housing for all tenants",
        "speaker_name" => "Jane Doe",
        "speaker_role" => "Executive Director"
      }
      other_tv = create(
        :news_article_text_version,
        news_article: news_article,
        extraction_status: "extracted",
        text: "New text version"
      )
      bna.update_columns(current_text_version_id: other_tv.id)
      expect(described_class.entry_still_grounded?(grounded_entry, bill: bill)).to be(false)
    end

    it "returns false if the excerpt does not exist in the article text" do
      bad_excerpt_entry = {
        "org_name" => "ACLU of Maryland",
        "stance" => "support",
        "summary" => "Supports fair housing.",
        "bill_news_article_id" => bna.id,
        "text_version_id" => text_version.id,
        "evidence_excerpt" => "Text that is not in the article",
        "speaker_name" => "Jane Doe",
        "speaker_role" => "Executive Director"
      }
      expect(described_class.entry_still_grounded?(bad_excerpt_entry, bill: bill)).to be(false)
    end

    it "returns false when the entry has evidence_retracted_at, when org_name is a public body or news outlet, or when the matched org has user memberships" do
      base_entry = {
        "org_name" => "ACLU of Maryland",
        "stance" => "support",
        "summary" => "Supports fair housing.",
        "bill_news_article_id" => bna.id,
        "text_version_id" => text_version.id,
        "evidence_excerpt" => "We strongly support this legislation to safeguard fair housing for all tenants",
        "speaker_name" => "Jane Doe",
        "speaker_role" => "Executive Director"
      }

      retracted_entry = base_entry.merge("evidence_retracted_at" => Time.current.utc.iso8601)
      expect(described_class.entry_still_grounded?(retracted_entry, bill: bill)).to be(false)

      public_body_entry = base_entry.merge("org_name" => "Baltimore City Council")
      expect(described_class.entry_still_grounded?(public_body_entry, bill: bill)).to be(false)

      outlet_entry = base_entry.merge("org_name" => "The Baltimore Banner")
      expect(described_class.entry_still_grounded?(outlet_entry, bill: bill)).to be(false)

      org = create(:organization, sway_locale: sway_locale, name: "ACLU of Maryland")
      create(:user_organization_membership, organization: org, user: user)
      expect(described_class.entry_still_grounded?(base_entry, bill: bill)).to be(false)
    end

    it "returns false for invalid or missing bill or entry" do
      grounded_entry = {
        "org_name" => "ACLU of Maryland",
        "stance" => "support",
        "summary" => "Supports fair housing.",
        "bill_news_article_id" => bna.id,
        "text_version_id" => text_version.id,
        "evidence_excerpt" => "We strongly support this legislation to safeguard fair housing for all tenants",
        "speaker_name" => "Jane Doe",
        "speaker_role" => "Executive Director"
      }
      expect(described_class.entry_still_grounded?(nil, bill: bill)).to be(false)
      expect(described_class.entry_still_grounded?(grounded_entry, bill: nil)).to be(false)
      expect(described_class.entry_still_grounded?("string", bill: bill)).to be(false)
    end
  end

  describe "decision model spokesperson authority verification" do
    let(:news_article) { create(:news_article, article_kind: "reporting", title: "Testimony Report") }
    let(:bna) do
      create(
        :bill_news_article,
        bill: bill,
        news_article: news_article,
        approved: true,
        approved_by: user,
        approved_at: Time.current
      )
    end
    let(:quoted_text) do
      "\"We strongly advocate for this tenant protection measure,\" said Taylor Smith, Senior Fellow at Baltimore Tenants Coalition."
    end
    let(:text_version) do
      create(
        :news_article_text_version,
        news_article: news_article,
        extraction_status: "extracted",
        text: quoted_text
      )
    end
    let(:draft_position) do
      {
        "org_name" => "Baltimore Tenants Coalition",
        "stance" => "support",
        "summary" => "Supports tenant protections.",
        "bill_news_article_id" => bna.id,
        "text_version_id" => text_version.id,
        "evidence_excerpt" => "We strongly advocate for this tenant protection measure",
        "speaker_name" => "Taylor Smith",
        "speaker_role" => "Senior Fellow"
      }
    end
    let(:decision_adapter) { instance_double(Llm::OpenRouterAdapter, provider_label: "openrouter") }
    let(:decision_route) do
      Llm::RouteResolver::Route.new(
        provider: :openrouter,
        api_model: "scaledown/classify-1",
        reasoning_effort: nil,
        mode: :decision
      )
    end

    def build_article_context(text, outlet_name: "The Baltimore Banner", author_name: "Pat Reporter")
      article = create(
        :news_article,
        article_kind: "reporting",
        outlet_name: outlet_name,
        author_name: author_name
      )
      tv = create(
        :news_article_text_version,
        news_article: article,
        extraction_status: "extracted",
        text: text
      )
      b_news_article = create(
        :bill_news_article,
        bill: bill,
        news_article: article,
        approved: true,
        approved_by: user,
        approved_at: Time.current,
        current_text_version_id: tv.id
      )
      bill.bill_news_articles.reload
      [b_news_article, tv]
    end

    before do
      bna.update_columns(current_text_version_id: text_version.id)
    end

    it "defines MIN_AUTHORITY_CONFIDENCE as 0.7 and DEFAULT_DECISION_MODEL as ScaleDown Classify Latest" do
      expect(described_class::MIN_AUTHORITY_CONFIDENCE).to eq(0.7)
      expect(described_class::DEFAULT_DECISION_MODEL).to eq("ScaleDown Classify Latest")
    end

    it "rejects non-regex leadership title when decision_adapter is nil" do
      results = described_class.filter_draft_positions(
        bill: bill,
        raw_positions: [draft_position],
        hearing_testimony_present: false,
        decision_adapter: nil
      )
      expect(results).to be_empty
    end

    it "accepts non-regex leadership title when decision model returns authorized_spokesperson with confidence >= 0.7" do
      expect(decision_adapter).to receive(:generate_decisions).with(
        model: "scaledown/classify-1",
        state: {
          "org_name" => "Baltimore Tenants Coalition",
          "speaker_role" => "Senior Fellow",
          "sentence" => quoted_text
        },
        questions: {
          "authority" => {
            "type" => "choice",
            "instructions" => "Does the speaker hold leadership or official spokesperson authority to state the organization's position in this sentence?",
            "criteria" => {
              "authorized_spokesperson" => "An officer, director, counsel, or authorized spokesperson speaking for the organization.",
              "official_statement" => "An official organizational statement.",
              "mere_member" => "A rank-and-file member, participant, or volunteer without leadership authority.",
              "unaffiliated" => "The speaker is not speaking on behalf of the organization."
            }
          }
        }
      ).and_return(
        {
          "answers" => {
            "authority" => {
              "type" => "choice",
              "choice" => "authorized_spokesperson",
              "confidence" => 0.85
            }
          }
        }
      )

      results = described_class.filter_draft_positions(
        bill: bill,
        raw_positions: [draft_position],
        hearing_testimony_present: false,
        decision_adapter: decision_adapter,
        decision_model: "scaledown/classify-1"
      )
      expect(results.size).to eq(1)
      expect(results.first["org_name"]).to eq("Baltimore Tenants Coalition")
    end

    it "reads confidence from probabilities hash when confidence key is absent" do
      allow(decision_adapter).to receive(:generate_decisions).and_return(
        {
          "answers" => {
            "authority" => {
              "type" => "choice",
              "choice" => "official_statement",
              "probabilities" => {
                "official_statement" => 0.75,
                "unaffiliated" => 0.25
              }
            }
          }
        }
      )

      results = described_class.filter_draft_positions(
        bill: bill,
        raw_positions: [draft_position],
        hearing_testimony_present: false,
        decision_adapter: decision_adapter,
        decision_model: "scaledown/classify-1"
      )
      expect(results.size).to eq(1)
    end

    it "rejects when choice is mere_member or unaffiliated even with high confidence" do
      allow(decision_adapter).to receive(:generate_decisions).and_return(
        {
          "answers" => {
            "authority" => {
              "type" => "choice",
              "choice" => "mere_member",
              "confidence" => 0.95
            }
          }
        }
      )

      results = described_class.filter_draft_positions(
        bill: bill,
        raw_positions: [draft_position],
        hearing_testimony_present: false,
        decision_adapter: decision_adapter,
        decision_model: "scaledown/classify-1"
      )
      expect(results).to be_empty
    end

    it "rejects when confidence is below 0.7" do
      allow(decision_adapter).to receive(:generate_decisions).and_return(
        {
          "answers" => {
            "authority" => {
              "type" => "choice",
              "choice" => "authorized_spokesperson",
              "confidence" => 0.65
            }
          }
        }
      )

      results = described_class.filter_draft_positions(
        bill: bill,
        raw_positions: [draft_position],
        hearing_testimony_present: false,
        decision_adapter: decision_adapter,
        decision_model: "scaledown/classify-1"
      )
      expect(results).to be_empty
    end

    it "resolves model via RouteResolver when decision_model parameter is omitted" do
      allow(Llm::RouteResolver).to receive(:resolve).with(
        purpose: :decision,
        blank_fallback: "ScaleDown Classify Latest"
      ).and_return(decision_route)

      expect(decision_adapter).to receive(:generate_decisions).with(
        model: "scaledown/classify-1",
        state: anything,
        questions: anything
      ).and_return(
        {
          "answers" => {
            "authority" => {
              "type" => "choice",
              "choice" => "authorized_spokesperson",
              "confidence" => 0.85
            }
          }
        }
      )

      results = described_class.filter_draft_positions(
        bill: bill,
        raw_positions: [draft_position],
        hearing_testimony_present: false,
        decision_adapter: decision_adapter
      )
      expect(results.size).to eq(1)
    end

    it "rejects mere-member matches deterministically without calling decision model" do
      volunteer_text = "\"We support this measure,\" said Pat Doe, a volunteer at Baltimore Tenants Coalition."
      tv = create(
        :news_article_text_version,
        news_article: news_article,
        extraction_status: "extracted",
        text: volunteer_text
      )
      bna.update_columns(current_text_version_id: tv.id)

      volunteer_draft = draft_position.merge(
        "text_version_id" => tv.id,
        "evidence_excerpt" => "We support this measure",
        "speaker_role" => "volunteer at Baltimore Tenants Coalition"
      )

      expect(decision_adapter).not_to receive(:generate_decisions)

      results = described_class.filter_draft_positions(
        bill: bill,
        raw_positions: [volunteer_draft],
        hearing_testimony_present: false,
        decision_adapter: decision_adapter
      )
      expect(results).to be_empty
    end

    it "accepts spokesperson matches deterministically without calling decision model" do
      director_text = "\"We support this measure,\" said Pat Doe, Executive Director of Baltimore Tenants Coalition."
      tv = create(
        :news_article_text_version,
        news_article: news_article,
        extraction_status: "extracted",
        text: director_text
      )
      bna.update_columns(current_text_version_id: tv.id)

      director_draft = draft_position.merge(
        "text_version_id" => tv.id,
        "evidence_excerpt" => "We support this measure",
        "speaker_role" => "Executive Director"
      )

      expect(decision_adapter).not_to receive(:generate_decisions)

      results = described_class.filter_draft_positions(
        bill: bill,
        raw_positions: [director_draft],
        hearing_testimony_present: false,
        decision_adapter: decision_adapter
      )
      expect(results.size).to eq(1)
    end

    it "rescues decision model errors, logs warning, and rejects safely" do
      allow(decision_adapter).to receive(:generate_decisions).and_raise(
        Llm::TransportError.new("connection timeout")
      )
      allow(SwayLogging).to receive(:warn)

      results = described_class.filter_draft_positions(
        bill: bill,
        raw_positions: [draft_position],
        hearing_testimony_present: false,
        decision_adapter: decision_adapter
      )
      expect(results).to be_empty
      expect(SwayLogging).to have_received(:warn).with(
        "news_grounding.decision_model_failed",
        hash_including(error_class: "Llm::TransportError")
      )
    end

    it "verifies authority via decision model in entry_still_grounded?" do
      allow(decision_adapter).to receive(:generate_decisions).and_return(
        {
          "answers" => {
            "authority" => {
              "type" => "choice",
              "choice" => "authorized_spokesperson",
              "confidence" => 0.88
            }
          }
        }
      )

      expect(
        described_class.entry_still_grounded?(
          draft_position,
          bill: bill,
          decision_adapter: decision_adapter,
          decision_model: "scaledown/classify-1"
        )
      ).to be(true)
    end

    it "resolves configured decision model and adapter when decision_adapter: :default outside Rails.env.test?" do
      allow(Rails.env).to receive(:test?).and_return(false)
      allow(Llm::RouteResolver).to receive(:resolve).with(
        purpose: :decision,
        blank_fallback: "ScaleDown Classify Latest"
      ).and_return(decision_route)
      allow(Llm::Client).to receive(:build).with(provider: "openrouter").and_return(decision_adapter)

      director_draft = draft_position.merge("speaker_role" => "Legislative Director")
      allow(decision_adapter).to receive(:generate_decisions).and_return(
        {
          "answers" => {
            "authority" => {
              "type" => "choice",
              "choice" => "authorized_spokesperson",
              "confidence" => 0.85
            }
          }
        }
      )

      results = described_class.filter_draft_positions(
        bill: bill,
        raw_positions: [director_draft],
        hearing_testimony_present: false
      )
      expect(results.size).to eq(1)

      still_grounded = described_class.entry_still_grounded?(director_draft, bill: bill)
      expect(still_grounded).to be(true)
    end

    it "rejects entries disqualified by public_body_name?, self_attribution?, organization_has_users?, or duplicate seen_orgs before calling decision_adapter.generate_decisions" do
      public_body_draft = draft_position.merge("org_name" => "Baltimore City Council")
      self_attr_draft = draft_position.merge("org_name" => news_article.outlet_name)
      org_with_users = create(:organization, sway_locale: bill.sway_locale, name: "Users Org")
      create(:user_organization_membership, organization: org_with_users, user: user)
      users_org_draft = draft_position.merge("org_name" => "Users Org")
      dup_draft_1 = draft_position.merge("org_name" => "Duplicate Org", "speaker_role" => "Executive Director")
      dup_draft_2 = draft_position.merge("org_name" => "The Duplicate Org, Inc.")

      expect(decision_adapter).not_to receive(:generate_decisions)

      described_class.filter_draft_positions(
        bill: bill,
        raw_positions: [public_body_draft, self_attr_draft, users_org_draft, dup_draft_1, dup_draft_2],
        hearing_testimony_present: false,
        decision_adapter: decision_adapter
      )
    end

    it "neutralizes prompt-boundary markers via Llm::UntrustedTextBlock.neutralize and caps org_name, speaker_role, and sentence" do
      long_org = "A" * 300
      long_role = "Senior Fellow " + ("B" * 300)
      long_sentence = ("C" * 1500)

      expect(decision_adapter).to receive(:generate_decisions) do |args|
        state = args[:state]
        expect(state["org_name"].length).to be <= described_class::MAX_ORG_NAME_CHARS
        expect(state["speaker_role"].length).to be <= described_class::MAX_SPEAKER_ROLE_CHARS
        expect(state["sentence"].length).to be <= described_class::MAX_SENTENCE_CHARS
        {
          "answers" => {
            "authority" => {
              "type" => "choice",
              "choice" => "authorized_spokesperson",
              "confidence" => 0.85
            }
          }
        }
      end

      described_class.send(
        :verify_with_decision_model,
        speaker_role: long_role,
        sentence: long_sentence,
        org_name: long_org,
        decision_adapter: decision_adapter,
        decision_model: "scaledown/classify-1"
      )
    end

    it "rejects confidence of Float::INFINITY" do
      allow(decision_adapter).to receive(:generate_decisions).and_return(
        {
          "answers" => {
            "authority" => {
              "type" => "choice",
              "choice" => "authorized_spokesperson",
              "confidence" => Float::INFINITY
            }
          }
        }
      )

      results = described_class.filter_draft_positions(
        bill: bill,
        raw_positions: [draft_position],
        hearing_testimony_present: false,
        decision_adapter: decision_adapter,
        decision_model: "scaledown/classify-1"
      )
      expect(results).to be_empty
    end

    it "rejects non-numeric string confidence '0.99'" do
      allow(decision_adapter).to receive(:generate_decisions).and_return(
        {
          "answers" => {
            "authority" => {
              "type" => "choice",
              "choice" => "authorized_spokesperson",
              "confidence" => "0.99"
            }
          }
        }
      )

      results = described_class.filter_draft_positions(
        bill: bill,
        raw_positions: [draft_position],
        hearing_testimony_present: false,
        decision_adapter: decision_adapter,
        decision_model: "scaledown/classify-1"
      )
      expect(results).to be_empty
    end

    it "rejects confidence 0.699 and accepts confidence 0.700" do
      allow(decision_adapter).to receive(:generate_decisions).and_return(
        {
          "answers" => {
            "authority" => {
              "type" => "choice",
              "choice" => "authorized_spokesperson",
              "confidence" => 0.699
            }
          }
        }
      )

      results_below = described_class.filter_draft_positions(
        bill: bill,
        raw_positions: [draft_position],
        hearing_testimony_present: false,
        decision_adapter: decision_adapter,
        decision_model: "scaledown/classify-1"
      )
      expect(results_below).to be_empty

      allow(decision_adapter).to receive(:generate_decisions).and_return(
        {
          "answers" => {
            "authority" => {
              "type" => "choice",
              "choice" => "authorized_spokesperson",
              "confidence" => 0.700
            }
          }
        }
      )

      results_at = described_class.filter_draft_positions(
        bill: bill,
        raw_positions: [draft_position],
        hearing_testimony_present: false,
        decision_adapter: decision_adapter,
        decision_model: "scaledown/classify-1"
      )
      expect(results_at.size).to eq(1)
    end

    it "blocks decision model when dual-role claim pairs mere-member with ambiguous title" do
      dual_role_text = "\"We favor tenant arbitration,\" said Jordan Lee, a member of the advisory panel and Senior Fellow at Civic Forum."
      bna_dual, tv_dual = build_article_context(dual_role_text)

      dual_draft = draft_position.merge(
        "bill_news_article_id" => bna_dual.id,
        "text_version_id" => tv_dual.id,
        "evidence_excerpt" => "We favor tenant arbitration",
        "speaker_role" => "Senior Fellow"
      )

      expect(decision_adapter).not_to receive(:generate_decisions)

      results = described_class.filter_draft_positions(
        bill: bill,
        raw_positions: [dual_draft],
        hearing_testimony_present: false,
        decision_adapter: decision_adapter
      )
      expect(results).to be_empty
    end

    it "never calls decision model when speaker_role matches mere-member, even with 100% confidence claim" do
      member_text = "\"We demand lower rent caps across the district,\" said Alex Roe, a member of Baltimore Tenants Union."
      bna_member, tv_member = build_article_context(member_text)

      member_draft = draft_position.merge(
        "bill_news_article_id" => bna_member.id,
        "text_version_id" => tv_member.id,
        "evidence_excerpt" => "We demand lower rent caps across the district",
        "speaker_role" => "a member of Baltimore Tenants Union"
      )

      expect(decision_adapter).not_to receive(:generate_decisions)

      results = described_class.filter_draft_positions(
        bill: bill,
        raw_positions: [member_draft],
        hearing_testimony_present: false,
        decision_adapter: decision_adapter
      )
      expect(results).to be_empty
    end

    it "rescues transport and schema errors, logs structured warning, and isolates failure in batch" do
      director_text = "\"We endorse this critical housing reform,\" said Robin Blair, Executive Director."
      bna1, tv1 = build_article_context(director_text)
      draft1 = draft_position.merge("bill_news_article_id" => bna1.id, "text_version_id" => tv1.id, "evidence_excerpt" => "We endorse this critical housing reform", "speaker_role" => "Executive Director", "org_name" => "Org One")

      partner_text = "\"Arbitration rules must be fair,\" said Blair Waldorf, Managing Partner."
      bna2, tv2 = build_article_context(partner_text)
      draft2 = draft_position.merge("bill_news_article_id" => bna2.id, "text_version_id" => tv2.id, "evidence_excerpt" => "Arbitration rules must be fair", "speaker_role" => "Managing Partner", "org_name" => "Org Two")

      fellow_text = "\"Zoning modernization is overdue,\" said Chuck Bass, Senior Fellow."
      bna3, tv3 = build_article_context(fellow_text)
      draft3 = draft_position.merge("bill_news_article_id" => bna3.id, "text_version_id" => tv3.id, "evidence_excerpt" => "Zoning modernization is overdue", "speaker_role" => "Senior Fellow", "org_name" => "Org Three")

      expect(decision_adapter).to receive(:generate_decisions).with(
        hash_including(state: hash_including("speaker_role" => "Managing Partner"))
      ).and_raise(Llm::TransportError.new("Connection refused by upstream endpoint"))

      expect(decision_adapter).to receive(:generate_decisions).with(
        hash_including(state: hash_including("speaker_role" => "Senior Fellow"))
      ).and_return(
        {
          "answers" => {
            "authority" => {
              "type" => "choice",
              "choice" => "authorized_spokesperson",
              "confidence" => 0.85
            }
          }
        }
      )

      expect(SwayLogging).to receive(:warn).with(
        "news_grounding.decision_model_failed",
        hash_including(error_class: "Llm::TransportError")
      )

      results = described_class.filter_draft_positions(
        bill: bill,
        raw_positions: [draft1, draft2, draft3],
        hearing_testimony_present: false,
        decision_adapter: decision_adapter,
        decision_model: "scaledown/classify-1"
      )

      expect(results.size).to eq(2)
      expect(results.pluck("org_name")).to contain_exactly("Org One", "Org Three")
    end

    it "rescues route resolution failure safely without bubbling exception" do
      allow(decision_adapter).to receive(:generate_decisions)
      allow(Llm::RouteResolver).to receive(:resolve).and_raise(
        RuntimeError.new("Model configuration missing for purpose decision")
      )
      expect(SwayLogging).to receive(:warn).with(
        "news_grounding.decision_model_failed",
        hash_including(error_class: "RuntimeError")
      )

      results = described_class.filter_draft_positions(
        bill: bill,
        raw_positions: [draft_position],
        hearing_testimony_present: false,
        decision_adapter: decision_adapter,
        decision_model: nil
      )
      expect(results).to be_empty
    end

    it "fails entry_still_grounded? when decision model confidence is 0.699" do
      allow(decision_adapter).to receive(:generate_decisions).and_return(
        {
          "answers" => {
            "authority" => {
              "type" => "choice",
              "choice" => "authorized_spokesperson",
              "confidence" => 0.699
            }
          }
        }
      )

      expect(
        described_class.entry_still_grounded?(
          draft_position,
          bill: bill,
          decision_adapter: decision_adapter,
          decision_model: "scaledown/classify-1"
        )
      ).to be(false)
    end

    it "fails entry_still_grounded? safely when decision adapter raises error" do
      allow(decision_adapter).to receive(:generate_decisions).and_raise(
        Llm::TransportError.new("Timeout communicating with OpenRouter")
      )
      allow(SwayLogging).to receive(:warn)

      expect(
        described_class.entry_still_grounded?(
          draft_position,
          bill: bill,
          decision_adapter: decision_adapter,
          decision_model: "scaledown/classify-1"
        )
      ).to be(false)
    end

    it "does not resolve decision adapter or route for pure deterministic batches outside Rails.env.test?" do
      allow(Rails.env).to receive(:test?).and_return(false)
      expect(described_class).not_to receive(:default_decision_adapter)
      expect(described_class).not_to receive(:default_decision_route)
      expect(Llm::RouteResolver).not_to receive(:resolve)

      director_text = "\"We endorse this critical housing reform,\" said Robin Blair, Executive Director."
      bna1, tv1 = build_article_context(director_text)
      draft1 = draft_position.merge("bill_news_article_id" => bna1.id, "text_version_id" => tv1.id, "evidence_excerpt" => "We endorse this critical housing reform", "speaker_role" => "Executive Director", "org_name" => "Org One")

      volunteer_text = "\"We support this measure,\" said Pat Doe, a volunteer at Baltimore Tenants Coalition."
      bna2, tv2 = build_article_context(volunteer_text)
      draft2 = draft_position.merge("bill_news_article_id" => bna2.id, "text_version_id" => tv2.id, "evidence_excerpt" => "We support this measure", "speaker_role" => "volunteer at Baltimore Tenants Coalition", "org_name" => "Org Two")

      results = described_class.filter_draft_positions(
        bill: bill,
        raw_positions: [draft1, draft2],
        hearing_testimony_present: false,
        decision_adapter: :default
      )

      expect(results.size).to eq(1)
      expect(results.first["org_name"]).to eq("Org One")
    end

    it "resolves decision route and adapter exactly once when an ambiguous draft is processed with default adapter" do
      allow(Rails.env).to receive(:test?).and_return(false)
      expect(Llm::RouteResolver).to receive(:resolve).with(
        purpose: :decision,
        blank_fallback: "ScaleDown Classify Latest"
      ).once.and_return(decision_route)
      expect(Llm::Client).to receive(:build).with(provider: "openrouter").once.and_return(decision_adapter)

      expect(decision_adapter).to receive(:generate_decisions).once.and_return(
        {
          "answers" => {
            "authority" => {
              "type" => "choice",
              "choice" => "authorized_spokesperson",
              "confidence" => 0.85
            }
          }
        }
      )

      results = described_class.filter_draft_positions(
        bill: bill,
        raw_positions: [draft_position],
        hearing_testimony_present: false,
        decision_adapter: :default
      )

      expect(results.size).to eq(1)
    end

    it "caches resolved decision route and client across multiple ambiguous drafts in a batch" do
      allow(Rails.env).to receive(:test?).and_return(false)
      expect(Llm::RouteResolver).to receive(:resolve).with(
        purpose: :decision,
        blank_fallback: "ScaleDown Classify Latest"
      ).once.and_return(decision_route)
      expect(Llm::Client).to receive(:build).with(provider: "openrouter").once.and_return(decision_adapter)

      partner_text = "\"Arbitration rules must be fair,\" said Blair Waldorf, Managing Partner."
      bna1, tv1 = build_article_context(partner_text)
      draft1 = draft_position.merge("bill_news_article_id" => bna1.id, "text_version_id" => tv1.id, "evidence_excerpt" => "Arbitration rules must be fair", "speaker_role" => "Managing Partner", "org_name" => "Org One")

      fellow_text = "\"Zoning modernization is overdue,\" said Chuck Bass, Senior Fellow."
      bna2, tv2 = build_article_context(fellow_text)
      draft2 = draft_position.merge("bill_news_article_id" => bna2.id, "text_version_id" => tv2.id, "evidence_excerpt" => "Zoning modernization is overdue", "speaker_role" => "Senior Fellow", "org_name" => "Org Two")

      expect(decision_adapter).to receive(:generate_decisions).twice.and_return(
        {
          "answers" => {
            "authority" => {
              "type" => "choice",
              "choice" => "authorized_spokesperson",
              "confidence" => 0.85
            }
          }
        }
      )

      results = described_class.filter_draft_positions(
        bill: bill,
        raw_positions: [draft1, draft2],
        hearing_testimony_present: false,
        decision_adapter: :default
      )

      expect(results.size).to eq(2)
      expect(results.pluck("org_name")).to contain_exactly("Org One", "Org Two")
    end
  end
end
