# frozen_string_literal: true

require "rails_helper"

RSpec.describe ParseSectionsService do
  include ActiveSupport::Testing::TimeHelpers

  # Build a bill in a fresh sway_locale so locale-isolation tests stay clean.
  def make_bill(extracted_text:, sway_locale: nil)
    sway_locale ||= create(:sway_locale)
    legislator = create(:legislator, district: create(:district, sway_locale: sway_locale))
    bill = create(:bill, sway_locale: sway_locale, legislator: legislator)
    bill.update_column(:extracted_text, extracted_text)
    bill.reload
  end

  # The service writes new BillSectionReference rows inside its own
  # transaction. Read them back with a fresh query: .destroy_all cleared the
  # cached association, so the caller never saw the new rows.
  def refs_for(bill)
    BillSectionReference.where(bill_id: bill.id).order(:ordinal)
  end

  def ops_for(bill)
    BillAmendmentOperation.where(bill_id: bill.id).order(:ordinal)
  end

  describe "happy-path text-pattern parse" do
    it "writes one BillSectionReference (:exact) and one BillAmendmentOperation (:strike, :text_pattern)" do
      sway_locale = create(:sway_locale)
      create(:law_section,
        sway_locale: sway_locale,
        key: "art_1__sec_5",
        article: "1",
        section: "5",
        title: "Repealable Provision",
        body: "Section body.")

      extracted = <<~TEXT.strip
        AN ORDINANCE concerning the Baltimore City Charter.

        Section § 1-5 of the City Charter is hereby repealed.
      TEXT
      bill = make_bill(extracted_text: extracted, sway_locale: sway_locale)

      result = described_class.new(bill: bill).call

      expect(result.section_reference_ids.length).to eq(1)
      expect(result.operation_ids.length).to eq(1)
      expect(result.amendment_source).to eq("text_pattern")

      ref = bill.bill_section_references.order(:ordinal).first
      expect(ref.resolution).to eq("exact")
      expect(ref.key).to eq("art_1__sec_5")

      op = bill.bill_amendment_operations.order(:ordinal).first
      expect(op.operation).to eq("strike")
      expect(op.source).to eq("text_pattern")
      expect(op.anchor_text).to eq("is hereby repealed")

      bill.reload
      expect(bill.amendment_source).to eq("text_pattern")
      expect(bill.parsing_target).to eq("charter")
      expect(bill.parsed_at).not_to be_nil
    end
  end

  describe "fuzzy resolution" do
    it "matches a one-char-off cite against the LawSection corpus" do
      sway_locale = create(:sway_locale)
      # The real key ends in 14; the bill cites 1-4, becoming key
      # art_1__sec_4 against LawSection.key art_1__sec_14. Fuzzy matching
      # scores that above 90, the threshold for keys of different lengths.
      create(:law_section, sway_locale: sway_locale,
        key: "art_1__sec_4",
        article: "1", section: "4", body: "Some section body.")
      create(:law_section, sway_locale: sway_locale,
        key: "art_1__sec_14XX", # near-miss alternate that must NOT win
        article: "1", section: "14XX", body: "Other section body.")

      extracted = "City Code: amend Section § 1-4XX. is hereby repealed."
      bill = make_bill(extracted_text: extracted, sway_locale: sway_locale)

      described_class.new(bill: bill).call

      ref = bill.bill_section_references.order(:ordinal).first
      expect(ref).not_to be_nil
      expect(ref.resolution).to be_in(%w[exact fuzzy])
      # If the match is fuzzy, fuzzy_score must be set and at least 90.
      if ref.resolution == "fuzzy"
        expect(ref.fuzzy_score).to be >= 90
      end
    end
  end

  describe "unresolved reference" do
    it "records :unresolved with fuzzy_score nil when the key is absent" do
      sway_locale = create(:sway_locale)
      extracted = "Section § 9-99 is hereby repealed."
      bill = make_bill(extracted_text: extracted, sway_locale: sway_locale)

      result = described_class.new(bill: bill).call

      ref = refs_for(bill).first
      expect(ref).not_to be_nil
      expect(ref.resolution).to eq("unresolved")
      expect(ref.fuzzy_score).to be_nil
      expect(ops_for(bill).first&.target_law_section_id).to be_nil
      expect(result.unresolved_keys).to include("art_9__sec_9-99")
    end
  end

  describe "REPLACE op storage (RESEARCH-REPLAN Pitfall 2)" do
    it "stores anchor_text=match, replacement_text=nil, operation=:replace, source=:text_pattern" do
      extracted = "Charter: striking foo and inserting bar from the section."
      bill = make_bill(extracted_text: extracted)

      described_class.new(bill: bill).call

      op = bill.bill_amendment_operations.first
      expect(op.operation).to eq("replace")
      expect(op.source).to eq("text_pattern")
      expect(op.anchor_text).to eq("striking foo and inserting")
      expect(op.replacement_text).to be_nil
    end
  end

  describe "INSERT op storage" do
    it "stores anchor_text=nil, replacement_text=match, operation=:insert" do
      extracted = "Charter: this Section is amended to read as follows: ..."
      bill = make_bill(extracted_text: extracted)

      described_class.new(bill: bill).call

      op = bill.bill_amendment_operations.first
      expect(op.operation).to eq("insert")
      expect(op.anchor_text).to be_nil
      expect(op.replacement_text).to eq("is amended to read as follows")
    end
  end

  describe "idempotency" do
    it "wipes prior rows and advances parsed_at on a second call" do
      sway_locale = create(:sway_locale)
      create(:law_section, sway_locale: sway_locale,
        key: "art_1__sec_5", article: "1", section: "5", body: "x")

      extracted = "Charter § 1-5 is hereby repealed."
      bill = make_bill(extracted_text: extracted, sway_locale: sway_locale)

      described_class.new(bill: bill).call
      first_parsed_at = bill.reload.parsed_at
      ref_count_a = refs_for(bill).count
      op_count_a = ops_for(bill).count

      travel_to 1.second.from_now do
        described_class.new(bill: bill.reload).call
        bill.reload
        expect(refs_for(bill).count).to eq(ref_count_a)
        expect(ops_for(bill).count).to eq(op_count_a)
        expect(bill.parsed_at).to be > first_parsed_at
      end
    end
  end

  describe "no markup.json read" do
    it "ignores legislation/bills/markup/<external_id>.json even when present" do
      sway_locale = create(:sway_locale)
      bill = make_bill(extracted_text: "Charter § 1-5 is hereby repealed.", sway_locale: sway_locale)

      markup_dir = Rails.root.join("legislation", "bills", "markup")
      FileUtils.mkdir_p(markup_dir)
      markup_path = markup_dir.join("#{bill.external_id}.json")
      sabotage_payload = {
        "operations" => [
          {"operation" => "STRIKE", "text" => "SABOTAGE_PAYLOAD_TEXT", "source" => "markup"}
        ]
      }
      File.write(markup_path, JSON.generate(sabotage_payload))

      begin
        described_class.new(bill: bill).call

        ops = bill.bill_amendment_operations.to_a
        expect(ops.map(&:source).uniq).not_to include("markup")
        expect(ops.map(&:anchor_text).compact + ops.map(&:replacement_text).compact)
          .not_to include(a_string_including("SABOTAGE_PAYLOAD_TEXT"))
      ensure
        FileUtils.rm_f(markup_path)
      end
    end
  end

  describe "locale-scoped LawSection lookup (Pitfall 5)" do
    it "resolves against the bill's locale, never cross-locale" do
      locale_a = create(:sway_locale)
      locale_b = create(:sway_locale)
      a_section = create(:law_section, sway_locale: locale_a,
        key: "art_1__sec_5", article: "1", section: "5", body: "Locale A body.")
      create(:law_section, sway_locale: locale_b,
        key: "art_1__sec_5", article: "1", section: "5", body: "Locale B body.")

      bill = make_bill(extracted_text: "§ 1-5 is hereby repealed.", sway_locale: locale_a)
      described_class.new(bill: bill).call

      ref = refs_for(bill).first
      expect(ref).not_to be_nil
      expect(ref.resolution).to eq("exact")
      attribution = ops_for(bill).first.target_law_section_id
      expect(attribution).to eq(a_section.id)
    end
  end

  describe "empty extracted_text" do
    it "raises BillProcessingError" do
      bill = create(:bill)
      bill.update_column(:extracted_text, nil)
      expect { described_class.new(bill: bill).call }.to raise_error(BillProcessingError)
    end
  end

  # @lat: [[legislation-pipeline#Parsed references are replaced together#The first header mention selects the body of law]]
  describe "choosing between the charter and the code" do
    it "reads the charter when the bill names it first, even in a wording that contains a later keyword" do
      bill = make_bill(
        extracted_text: "Charter of Baltimore City, Article 1. Amends the " \
          "City Code as well. See also the City Charter."
      )

      described_class.new(bill: bill).call

      expect(bill.reload.parsing_target).to eq("charter")
    end

    it "reads the code when the bill names the code first" do
      bill = make_bill(
        extracted_text: "City Code, Article 5. This does not touch the " \
          "Charter of Baltimore City."
      )

      described_class.new(bill: bill).call

      expect(bill.reload.parsing_target).to eq("code")
    end
  end

  describe "hyphenated section citation normalization" do
    it "resolves § 10-18 directly against art_10__sec_10-18 as :exact" do
      sway_locale = create(:sway_locale)
      law_sec = create(:law_section,
        sway_locale: sway_locale,
        key: "art_10__sec_10-18",
        article: "10",
        section: "10-18",
        title: "High-performance market-rate rental housing")

      extracted = "City Code: § 10-18 is hereby repealed."
      bill = make_bill(extracted_text: extracted, sway_locale: sway_locale)

      result = described_class.new(bill: bill).call

      ref = refs_for(bill).first
      expect(ref).not_to be_nil
      expect(ref.resolution).to eq("exact")
      expect(ref.key).to eq("art_10__sec_10-18")
      expect(ref.article).to eq("10")
      expect(ref.section).to eq("10-18")
      expect(ops_for(bill).first&.target_law_section_id).to eq(law_sec.id)
      expect(result.unresolved_keys).to be_empty
    end

    it "falls back via two-shape lookup when section in corpus is not article-prefixed" do
      sway_locale = create(:sway_locale)
      law_sec = create(:law_section,
        sway_locale: sway_locale,
        key: "art_1__sec_5",
        article: "1",
        section: "5",
        title: "General Provisions")

      extracted = "City Code: § 1-5 is hereby repealed."
      bill = make_bill(extracted_text: extracted, sway_locale: sway_locale)

      described_class.new(bill: bill).call

      ref = refs_for(bill).first
      expect(ref).not_to be_nil
      expect(ref.resolution).to eq("exact")
      expect(ref.key).to eq("art_1__sec_5")
      expect(ops_for(bill).first&.target_law_section_id).to eq(law_sec.id)
    end
  end

  describe "declared amendment target parsing from BY header" do
    let(:sway_locale) { create(:sway_locale) }
    let!(:target_law_sec) do
      create(:law_section,
        sway_locale: sway_locale,
        key: "art_19__sec_61-3",
        article: "19",
        section: "61-3",
        title: "Registration — In general")
    end
    let!(:incidental_law_sec) do
      create(:law_section,
        sway_locale: sway_locale,
        key: "art_1__sec_5",
        article: "1",
        section: "5",
        title: "Employees Retirement System")
    end

    let(:bill_text) do
      <<~TEXT
        AN ORDINANCE CONCERNING
        Arson Offender Registry — Registration Requirement

        FOR the purpose of altering the criteria for registering as an arson offender.

        BY repealing and re-ordaining, with amendments,

        Article 19 — Police Ordinances
        Section 61-3(a)

        Baltimore City Code

        (Edition 2000)

        SECTION 1. BE IT ORDAINED BY THE MAYOR AND CITY COUNCIL OF BALTIMORE, That the
        Laws of Baltimore City read as follows:

        Baltimore City Code
        Article 19. Police Ordinances
        Subtitle 61. Arson Offender Registration
        § 61-3. Registration — In general.

        (a) Registration required.
        An arson offender must register with the Commissioner. is hereby repealed.

        SECTION 2. Cross-reference to Article 1, Section 5 for pension administration.
      TEXT
    end

    it "parses declared target as ordinal 0 with authoritative: true" do
      bill = make_bill(extracted_text: bill_text, sway_locale: sway_locale)
      described_class.new(bill: bill).call

      refs = refs_for(bill).to_a
      expect(refs.size).to eq(2)

      target_ref = refs.first
      expect(target_ref.ordinal).to eq(0)
      expect(target_ref.authoritative).to be(true)
      expect(target_ref.resolution).to eq("exact")
      expect(target_ref.key).to eq("art_19__sec_61-3")
      expect(target_ref.article).to eq("19")
      expect(target_ref.section).to eq("61-3")

      body_ref = refs.second
      expect(body_ref.ordinal).to eq(1)
      expect(body_ref.authoritative).to be(false)
      expect(body_ref.resolution).to eq("exact")
      expect(body_ref.key).to eq("art_1__sec_5")
    end

    it "attributes SECTION 1 operations to the authoritative target" do
      bill = make_bill(extracted_text: bill_text, sway_locale: sway_locale)
      described_class.new(bill: bill).call

      ops = ops_for(bill).to_a
      expect(ops.size).to be >= 1

      primary_op = ops.first
      expect(primary_op.target_law_section_id).to eq(target_law_sec.id)
      expect(primary_op.bill_section_reference_id).to eq(refs_for(bill).first.id)
    end

    it "assigns authoritative: false and ordinals from 0 when no BY header exists" do
      text = "City Code: Article 1, Section 5 is hereby repealed."
      bill = make_bill(extracted_text: text, sway_locale: sway_locale)
      described_class.new(bill: bill).call

      refs = refs_for(bill).to_a
      expect(refs.size).to eq(1)
      expect(refs.first.ordinal).to eq(0)
      expect(refs.first.authoritative).to be(false)
    end
  end

  describe "typographic markup extraction" do
    it "extracts :strike and :insert ops and sets amendment_source to 'markup'" do
      sway_locale = create(:sway_locale)
      create(:law_section, sway_locale: sway_locale, key: "art_1__sec_5", article: "1", section: "5", title: "T", body: "body")
      extracted = <<~TEXT
        EXPLANATION: CAPITALS indicate matter added to existing law.
        [Brackets] indicate matter deleted from existing law.

        SECTION 1. BE IT ORDAINED BY THE MAYOR AND CITY COUNCIL OF BALTIMORE, That:
        Section § 1-5. An offender must register with [Commissioner of Police.] POLICE COMMISSIONER OF BALTIMORE CITY.
      TEXT
      bill = make_bill(extracted_text: extracted, sway_locale: sway_locale)

      result = described_class.new(bill: bill).call

      expect(result.amendment_source).to eq("markup")
      expect(bill.reload.amendment_source).to eq("markup")
      expect(result.operation_ids.size).to eq(2)

      ops = bill.bill_amendment_operations.order(:ordinal).to_a
      expect(ops.pluck(:source).uniq).to eq(["markup"])

      strike_op = ops.find { |o| o.operation == "strike" }
      expect(strike_op.anchor_text).to eq("Commissioner of Police.")
      expect(strike_op.replacement_text).to be_nil

      insert_op = ops.find { |o| o.operation == "insert" }
      expect(insert_op.anchor_text).to be_nil
      expect(insert_op.replacement_text).to eq("POLICE COMMISSIONER OF BALTIMORE CITY")
    end
  end

  describe "Maryland single-bill parsing" do
    let(:maryland) { create(:sway_locale, :maryland) }
    let(:baltimore) { create(:sway_locale, :baltimore) }

    it "resolves Annotated Code of Maryland citations against the Maryland jurisdiction only" do
      md_section = create(:law_section,
        sway_locale: maryland,
        key: "art_Transportation__sec_21-801",
        article: "Transportation",
        section: "21-801",
        title: "Speed restrictions")
      # Same key in Baltimore must never be resolved
      create(:law_section,
        sway_locale: baltimore,
        key: "art_Transportation__sec_21-801",
        article: "Transportation",
        section: "21-801",
        title: "Baltimore decoy section")

      text = <<~TEXT
        A BILL ENTITLED
        AN ACT concerning
        Vehicle Laws - Speed Monitoring Systems

        FOR the purpose of amending vehicle speed monitoring laws.
        BY repealing and reenacting, with amendments,
        Article - Transportation
        Section 21-801
        Annotated Code of Maryland

        SECTION 1. BE IT ENACTED BY THE GENERAL ASSEMBLY OF MARYLAND, That the Laws of Maryland read as follows:
        Article - Transportation
        Section 21-801 of the Transportation Article is hereby amended to read as follows:
      TEXT

      bill = make_bill(extracted_text: text, sway_locale: maryland)
      result = described_class.new(bill: bill).call

      expect(bill.reload.parsing_target).to eq("code")
      expect(result.no_sections_found).to be(false)

      refs = refs_for(bill).to_a
      expect(refs.size).to eq(1)
      ref = refs.first
      expect(ref.article).to eq("Transportation")
      expect(ref.section).to eq("21-801")
      expect(ref.resolution).to eq("exact")
      expect(ops_for(bill).first.target_law_section_id).to eq(md_section.id)
      expect(ref.authoritative).to be(true)
    end

    it "handles a non-amending Maryland resolution cleanly without inventing changes" do
      text = <<~TEXT
        SENATE RESOLUTION 123
        A SENATE RESOLUTION concerning Civic Engagement Week

        FOR the purpose of recognizing Civic Engagement Week in Maryland.
        WHEREAS, civic engagement is vital to our democracy; now, therefore, be it
        RESOLVED BY THE SENATE OF MARYLAND, That the Senate recognizes Civic Engagement Week.
      TEXT

      bill = make_bill(extracted_text: text, sway_locale: maryland)
      result = described_class.new(bill: bill).call

      expect(result.no_sections_found).to be(true)
      expect(result.section_reference_ids).to be_empty
      expect(result.operation_ids).to be_empty
      expect(result.amendment_source).to eq("none")
      expect(refs_for(bill)).to be_empty
      expect(ops_for(bill)).to be_empty
    end

    it "fails with a diagnostic error when Maryland bill text is genuinely missing" do
      bill = make_bill(extracted_text: nil, sway_locale: maryland)
      expect { described_class.new(bill: bill).call }
        .to raise_error(BillProcessingError, /has no extracted_text/)
    end

    describe "MGA statutory citations with Unicode en-dashes and subsection designators" do
      it "extracts declared target from MGA BY header with Unicode en-dashes and normalizes to ASCII hyphens" do
        tax_prop_sec = create(:law_section,
          sway_locale: maryland,
          key: "art_gtp__sec_7-521",
          article: "gtp",
          section: "7-521",
          title: "Article - Tax - Property § 7-521",
          body: "(a) Property tax agreement provisions.")

        extracted = <<~TEXT
          A BILL ENTITLED
          AN ACT concerning
          Property Tax - Payment in Lieu of Taxes Agreements - Broadband Service Providers

          EXPLANATION: CAPITALS indicate matter added to existing law.
          [Brackets] indicate matter deleted from existing law.

          FOR the purpose of authorizing local governments to enter into agreements.
          BY repealing and reenacting, with amendments,
          Article – Tax – Property
          Section 7–521
          Annotated Code of Maryland
          (2019 Replacement Volume and 2025 Supplement)

          SECTION 1. BE IT ENACTED BY THE GENERAL ASSEMBLY OF MARYLAND, That the Laws of Maryland read as follows:
          Article – Tax – Property
          7–521.
          (a) Local governments may enter into [agreements] CONTRACTS WITH BROADBAND PROVIDERS.
        TEXT

        bill = make_bill(extracted_text: extracted, sway_locale: maryland)
        result = described_class.new(bill: bill).call

        expect(result.no_sections_found).to be(false)
        refs = refs_for(bill).to_a
        expect(refs.size).to eq(1)

        ref = refs.first
        expect(ref.ordinal).to eq(0)
        expect(ref.authoritative).to be(true)
        expect(ref.resolution).to eq("exact")
        expect(ref.key).to eq("art_gtp__sec_7-521")
        expect(ref.article).to eq("gtp")
        expect(ref.section).to eq("7-521")
        expect(ref.title).to eq("Article - Tax - Property § 7-521")
        expect(ref.anchor).to include("Article – Tax – Property")
        expect(ref.anchor).to include("Section 7–521")

        ops = ops_for(bill).to_a
        expect(ops.size).to be >= 1
        expect(ops.first.target_law_section_id).to eq(tax_prop_sec.id)
        expect(ops.first.bill_section_reference_id).to eq(ref.id)
        expect(result.unresolved_keys).to be_empty
      end

      it "extracts in-body citations with Unicode en-dashes and parenthetical subsection suffixes, stripping subsection from section token while preserving anchor" do
        create(:law_section,
          sway_locale: maryland,
          key: "art_gtp__sec_9-305",
          article: "gtp",
          section: "9-305",
          title: "Article - Tax - Property § 9-305",
          body: "(j) Mandatory property tax credit.")

        extracted = <<~TEXT
          A BILL ENTITLED
          AN ACT concerning
          Tax - Property - Mandatory Tax Credits

          FOR the purpose of altering certain tax credit provisions.
          BY repealing and reenacting, with amendments,
          Article – Tax – Property
          Section 9–305(j)
          Annotated Code of Maryland
          (2019 Replacement Volume and 2025 Supplement)

          SECTION 1. BE IT ENACTED BY THE GENERAL ASSEMBLY OF MARYLAND, That the Laws of Maryland read as follows:
          Article – Tax – Property
          9–305.
          (j) In Section 9–305(j) of the Tax – Property Article, the credit is [25%] 50%.
        TEXT

        bill = make_bill(extracted_text: extracted, sway_locale: maryland)
        result = described_class.new(bill: bill).call

        refs = refs_for(bill).to_a
        expect(refs.size).to eq(1)

        ref = refs.first
        expect(ref.key).to eq("art_gtp__sec_9-305")
        expect(ref.article).to eq("gtp")
        expect(ref.section).to eq("9-305")
        expect(ref.resolution).to eq("exact")
        expect(ref.authoritative).to be(true)
        expect(ref.anchor).to include("Section 9–305(j)")
        expect(result.unresolved_keys).to be_empty
      end

      it "extracts inverted § <section> of the <Article> Article citations without triggering Baltimore short-form false positives" do
        create(:law_section,
          sway_locale: maryland,
          key: "art_gin__sec_15-144",
          article: "gin",
          section: "15-144",
          title: "Article - Insurance § 15-144",
          body: "Health care provider credentialing.")

        extracted = <<~TEXT
          A BILL ENTITLED
          AN ACT concerning
          Health Insurance - Credentialing

          SECTION 1. BE IT ENACTED BY THE GENERAL ASSEMBLY OF MARYLAND, That:
          In § 15–144 of the Insurance Article, a carrier shall [notify] INFORM the provider.
        TEXT

        bill = make_bill(extracted_text: extracted, sway_locale: maryland)
        described_class.new(bill: bill).call

        refs = refs_for(bill).to_a
        expect(refs.size).to eq(1)

        ref = refs.first
        expect(ref.key).to eq("art_gin__sec_15-144")
        expect(ref.article).to eq("gin")
        expect(ref.section).to eq("15-144")
        expect(ref.resolution).to eq("exact")
        expect(ref.authoritative).to be(false)
        expect(ref.anchor).to eq("§ 15–144 of the Insurance Article")
        # Ensure Baltimore short-form '15' was not falsely matched
        expect(ref.article).not_to eq("15")
        expect(ref.key).not_to eq("art_15__sec_15-144")
      end

      it "restricts article and section captures to horizontal whitespace and does not capture across newlines" do
        create(:law_section,
          sway_locale: maryland,
          key: "art_gtp__sec_7-521",
          article: "gtp",
          section: "7-521",
          title: "Article - Tax - Property § 7-521",
          body: "Body.")

        extracted = <<~TEXT
          A BILL ENTITLED
          Article – Tax – Property
          Preamble line 1 explaining why this bill is important.
          Preamble line 2 without section citation.
          Section 7–521 of the Tax – Property Article is hereby amended.
        TEXT

        bill = make_bill(extracted_text: extracted, sway_locale: maryland)
        described_class.new(bill: bill).call

        refs = refs_for(bill).to_a
        expect(refs.size).to eq(1)
        expect(refs.first.article).to eq("gtp")
        expect(refs.first.section).to eq("7-521")
        expect(refs.first.anchor).not_to include("Preamble line 1")
      end
    end

    describe "competing LawSections across different articles" do
      it "deterministically resolves Tax - Property § 7-521 citation to gtp LawSection and links operation" do
        tax_section = create(:law_section,
          sway_locale: maryland,
          key: "art_gtp__sec_7-521",
          article: "gtp",
          section: "7-521",
          title: "Article - Tax - Property § 7-521",
          body: "Tax - Property § 7-521 body.")
        insurance_section = create(:law_section,
          sway_locale: maryland,
          key: "art_gin__sec_7-521",
          article: "gin",
          section: "7-521",
          title: "Article - Insurance § 7-521",
          body: "Insurance § 7-521 body.")

        text = <<~TEXT
          A BILL ENTITLED
          AN ACT concerning Tax - Property

          EXPLANATION: CAPITALS indicate matter added to existing law.
          [Brackets] indicate matter deleted from existing law.

          BY repealing and reenacting, with amendments,
          Article – Tax – Property
          Section 7–521
          Annotated Code of Maryland

          SECTION 1. BE IT ENACTED BY THE GENERAL ASSEMBLY OF MARYLAND:
          Article – Tax – Property
          7–521.
          [Old property tax term] NEW PROPERTY TAX TERM HERE.
        TEXT

        bill = make_bill(extracted_text: text, sway_locale: maryland)
        result = described_class.new(bill: bill).call

        refs = refs_for(bill).to_a
        expect(refs.size).to eq(1)

        ref = refs.first
        expect(ref.key).to eq("art_gtp__sec_7-521")
        expect(ref.article).to eq("gtp")
        expect(ref.section).to eq("7-521")
        expect(ref.title).to eq("Article - Tax - Property § 7-521")
        expect(ref.resolution).to eq("exact")
        expect(ref.authoritative).to be(true)

        ops = ops_for(bill).to_a
        expect(ops.size).to be >= 1
        expect(ops.first.target_law_section_id).to eq(tax_section.id)
        expect(ops.first.target_law_section_id).not_to eq(insurance_section.id)
        expect(ops.first.bill_section_reference_id).to eq(ref.id)
        expect(result.unresolved_keys).to be_empty
      end

      it "deterministically resolves Insurance § 7-521 citation to gin LawSection and links operation" do
        tax_section = create(:law_section,
          sway_locale: maryland,
          key: "art_gtp__sec_7-521",
          article: "gtp",
          section: "7-521",
          title: "Article - Tax - Property § 7-521",
          body: "Tax - Property § 7-521 body.")
        insurance_section = create(:law_section,
          sway_locale: maryland,
          key: "art_gin__sec_7-521",
          article: "gin",
          section: "7-521",
          title: "Article - Insurance § 7-521",
          body: "Insurance § 7-521 body.")

        text = <<~TEXT
          A BILL ENTITLED
          AN ACT concerning Insurance

          EXPLANATION: CAPITALS indicate matter added to existing law.
          [Brackets] indicate matter deleted from existing law.

          BY repealing and reenacting, with amendments,
          Article – Insurance
          Section 7–521
          Annotated Code of Maryland

          SECTION 1. BE IT ENACTED BY THE GENERAL ASSEMBLY OF MARYLAND:
          Article – Insurance
          7–521.
          [Old insurance term] NEW INSURANCE TERM HERE.
        TEXT

        bill = make_bill(extracted_text: text, sway_locale: maryland)
        result = described_class.new(bill: bill).call

        refs = refs_for(bill).to_a
        expect(refs.size).to eq(1)

        ref = refs.first
        expect(ref.key).to eq("art_gin__sec_7-521")
        expect(ref.article).to eq("gin")
        expect(ref.section).to eq("7-521")
        expect(ref.title).to eq("Article - Insurance § 7-521")
        expect(ref.resolution).to eq("exact")
        expect(ref.authoritative).to be(true)

        ops = ops_for(bill).to_a
        expect(ops.size).to be >= 1
        expect(ops.first.target_law_section_id).to eq(insurance_section.id)
        expect(ops.first.target_law_section_id).not_to eq(tax_section.id)
        expect(ops.first.bill_section_reference_id).to eq(ref.id)
        expect(result.unresolved_keys).to be_empty
      end
    end

    describe "adding brand-new unindexed sections in indexed Maryland articles" do
      before do
        create(:law_section,
          sway_locale: maryland,
          key: "art_gin__sec_7-521",
          article: "gin",
          section: "7-521",
          title: "Article - Insurance § 7-521",
          body: "Existing insurance section.")
      end

      it "normalizes unresolved reference to canonical article code 'gin' and key 'art_gin__sec_15-2201'" do
        text = <<~TEXT
          A BILL ENTITLED
          AN ACT concerning
          Insurance - Dental Provider Networks

          EXPLANATION: CAPITALS indicate matter added to existing law.
          [Brackets] indicate matter deleted from existing law.

          FOR the purpose of establishing dental network requirements.
          BY adding to
          Article – Insurance
          Section 15–2201
          Annotated Code of Maryland
          (2017 Replacement Volume and 2025 Supplement)

          SECTION 1. BE IT ENACTED BY THE GENERAL ASSEMBLY OF MARYLAND, That the Laws of Maryland read as follows:
          Article – Insurance
          15–2201.
          (A) IN THIS SUBTITLE THE FOLLOWING WORDS HAVE THE MEANINGS INDICATED.
        TEXT

        bill = make_bill(extracted_text: text, sway_locale: maryland)
        result = described_class.new(bill: bill).call

        refs = refs_for(bill).to_a
        expect(refs.size).to eq(1)

        ref = refs.first
        expect(ref.ordinal).to eq(0)
        expect(ref.authoritative).to be(true)
        expect(ref.resolution).to eq("unresolved")
        expect(ref.fuzzy_score).to be_nil
        expect(ref.key).to eq("art_gin__sec_15-2201")
        expect(ref.article).to eq("gin")
        expect(ref.section).to eq("15-2201")
        expect(ref.title).to be_nil

        ops = ops_for(bill).to_a
        expect(ops.size).to be >= 1
        expect(ops.first.target_law_section_id).to be_nil
        expect(ops.first.bill_section_reference_id).to eq(ref.id)

        expect(result.unresolved_keys).to include("art_gin__sec_15-2201")
        expect(result.unresolved_keys).not_to include("art_Insurance__sec_15-2201")
      end
    end

    describe "multi-BY MGA headers with PDF margin line numbers" do
      it "selects the first non-without-amendments BY block as authoritative and preserves other BY blocks as non-authoritative" do
        sec_15_102 = create(:law_section,
          sway_locale: maryland,
          key: "art_gel__sec_15-102",
          article: "gel",
          section: "15-102",
          title: "Article - Election Law § 15-102",
          body: "(a) In this title the following words have the meanings indicated.")
        sec_15_107 = create(:law_section,
          sway_locale: maryland,
          key: "art_gel__sec_15-107",
          article: "gel",
          section: "15-107",
          title: "Article - Election Law § 15-107",
          body: "(a) Distribution schedule.")

        text = <<~TEXT
          A BILL ENTITLED
          AN ACT concerning
          Public Financing Act – Fair Campaign Financing Fund – Distributions

          EXPLANATION: CAPITALS INDICATE MATTER ADDED TO EXISTING LAW.
          [Brackets] indicate matter deleted from existing law.

          BY repealing and reenacting, without amendments,
          6

          Article – Election Law
          7

          Section 15–102(a) and (f)
          8

          Annotated Code of Maryland
          9

          (2022 Replacement Volume and 2025 Supplement)
          10

          BY repealing and reenacting, with amendments,
          11

          Article – Election Law
          12

          Section 15–107(a)
          13

          Annotated Code of Maryland
          14

          (2022 Replacement Volume and 2025 Supplement)
          15

          SECTION 1. BE IT ENACTED BY THE GENERAL ASSEMBLY OF MARYLAND,
          16
          That the Laws of Maryland read as follows:
          17
          Article – Election Law
          18
          15–102.
          19
          (a) In this title the following words have the meanings indicated.
          15–107.
          (a) The State Board may distribute [funds] PUBLIC CAMPAIGN FUNDS.
        TEXT

        bill = make_bill(extracted_text: text, sway_locale: maryland)
        result = described_class.new(bill: bill).call

        refs = refs_for(bill).to_a
        expect(refs.size).to eq(2)

        auth_ref = refs.find(&:authoritative)
        non_auth_ref = refs.find { |r| !r.authoritative }

        expect(auth_ref).not_to be_nil
        expect(auth_ref.ordinal).to eq(0)
        expect(auth_ref.key).to eq("art_gel__sec_15-107")
        expect(auth_ref.article).to eq("gel")
        expect(auth_ref.section).to eq("15-107")
        expect(auth_ref.resolution).to eq("exact")

        expect(non_auth_ref).not_to be_nil
        expect(non_auth_ref.ordinal).to eq(1)
        expect(non_auth_ref.key).to eq("art_gel__sec_15-102")
        expect(non_auth_ref.article).to eq("gel")
        expect(non_auth_ref.section).to eq("15-102")
        expect(non_auth_ref.resolution).to eq("exact")

        ops = ops_for(bill).to_a
        expect(ops.size).to be >= 1
        expect(ops.first.target_law_section_id).to eq(sec_15_107.id)
        expect(ops.first.target_law_section_id).not_to eq(sec_15_102.id)
        expect(ops.first.bill_section_reference_id).to eq(auth_ref.id)
        expect(result.unresolved_keys).to be_empty
      end

      it "falls back to the first BY block when all BY blocks in the header are without amendments" do
        create(:law_section,
          sway_locale: maryland,
          key: "art_gel__sec_15-102",
          article: "gel",
          section: "15-102",
          title: "Article - Election Law § 15-102",
          body: "Definitions.")
        create(:law_section,
          sway_locale: maryland,
          key: "art_gel__sec_15-103",
          article: "gel",
          section: "15-103",
          title: "Article - Election Law § 15-103",
          body: "Administration.")

        text = <<~TEXT
          A BILL ENTITLED
          BY repealing and reenacting, without amendments,
          6
          Article – Election Law
          7
          Section 15–102(a)
          Annotated Code of Maryland

          BY repealing and reenacting, without amendments,
          11
          Article – Election Law
          12
          Section 15–103(b)
          Annotated Code of Maryland

          SECTION 1. BE IT ENACTED BY THE GENERAL ASSEMBLY OF MARYLAND:
        TEXT

        bill = make_bill(extracted_text: text, sway_locale: maryland)
        described_class.new(bill: bill).call

        refs = refs_for(bill).to_a
        expect(refs.size).to eq(2)
        expect(refs.first.key).to eq("art_gel__sec_15-102")
        expect(refs.first.authoritative).to be(true)
        expect(refs.second.key).to eq("art_gel__sec_15-103")
        expect(refs.second.authoritative).to be(false)
      end

      it "deduplicates when a without-amendments BY block and a with-amendments BY block cite different subsections of the same section" do
        sec_15_1208 = create(:law_section,
          sway_locale: maryland,
          key: "art_gin__sec_15-1208.1",
          article: "gin",
          section: "15-1208.1",
          title: "Article - Insurance § 15-1208.1",
          body: "Special enrollment periods.")

        text = <<~TEXT
          A BILL ENTITLED
          EXPLANATION: CAPITALS INDICATE MATTER ADDED TO EXISTING LAW.
          [Brackets] indicate matter deleted from existing law.

          BY repealing and reenacting, without amendments,
          8
          Article – Insurance
          9
          Section 15–1208.1(c)
          Annotated Code of Maryland

          BY repealing and reenacting, with amendments,
          13
          Article – Insurance
          14
          Section 15–1208.1(f)(1)(v)
          Annotated Code of Maryland

          SECTION 1. BE IT ENACTED BY THE GENERAL ASSEMBLY OF MARYLAND:
          15–1208.1.
          (f)(1)(v) [Old enrollment rule] NEW ENROLLMENT RULE.
        TEXT

        bill = make_bill(extracted_text: text, sway_locale: maryland)
        described_class.new(bill: bill).call

        refs = refs_for(bill).to_a
        expect(refs.size).to eq(1)
        expect(refs.first.key).to eq("art_gin__sec_15-1208.1")
        expect(refs.first.authoritative).to be(true)
        expect(refs.first.anchor).to include("with amendments")
        expect(ops_for(bill).first.target_law_section_id).to eq(sec_15_1208.id)
      end
    end

    describe "cross-article same-section-number citations with a declared target" do
      it "preserves cross-article citations sharing the declared target's section number while deduplicating same-article repeats" do
        tax_sec = create(:law_section,
          sway_locale: maryland,
          key: "art_gtp__sec_1-101",
          article: "gtp",
          section: "1-101",
          title: "Article - Tax - Property § 1-101",
          body: "Tax - Property definitions.")
        ins_sec = create(:law_section,
          sway_locale: maryland,
          key: "art_gin__sec_1-101",
          article: "gin",
          section: "1-101",
          title: "Article - Insurance § 1-101",
          body: "Insurance definitions.")

        text = <<~TEXT
          A BILL ENTITLED
          AN ACT concerning Cross-Article Definitions

          EXPLANATION: CAPITALS indicate matter added to existing law.
          [Brackets] indicate matter deleted from existing law.

          BY repealing and reenacting, with amendments,
          Article – Tax – Property
          Section 1–101
          Annotated Code of Maryland

          SECTION 1. BE IT ENACTED BY THE GENERAL ASSEMBLY OF MARYLAND:
          Section 1–101 of the Tax – Property Article is amended.
          [Old tax definition] NEW TAX DEFINITION.

          SECTION 2. AND BE IT FURTHER ENACTED:
          Section 1–101 of the Insurance Article is also referenced.
        TEXT

        bill = make_bill(extracted_text: text, sway_locale: maryland)
        result = described_class.new(bill: bill).call

        refs = refs_for(bill).to_a
        expect(refs.size).to eq(2)

        auth_ref = refs.first
        expect(auth_ref.ordinal).to eq(0)
        expect(auth_ref.authoritative).to be(true)
        expect(auth_ref.key).to eq("art_gtp__sec_1-101")
        expect(auth_ref.article).to eq("gtp")
        expect(auth_ref.section).to eq("1-101")
        expect(auth_ref.resolution).to eq("exact")

        cross_ref = refs.second
        expect(cross_ref.ordinal).to eq(1)
        expect(cross_ref.authoritative).to be(false)
        expect(cross_ref.key).to eq("art_gin__sec_1-101")
        expect(cross_ref.article).to eq("gin")
        expect(cross_ref.section).to eq("1-101")
        expect(cross_ref.resolution).to eq("exact")

        ops = ops_for(bill).to_a
        expect(ops.first.target_law_section_id).to eq(tax_sec.id)
        expect(ops.first.target_law_section_id).not_to eq(ins_sec.id)
        expect(result.unresolved_keys).to be_empty
      end

      it "still deduplicates a Baltimore short-form repeat (§ 4-1) against a Baltimore BY header (Article 1, Section 4-1)" do
        create(:law_section,
          sway_locale: baltimore,
          key: "art_1__sec_4-1",
          article: "1",
          section: "4-1",
          title: "General Provisions § 4-1",
          body: "Baltimore City Code § 4-1.")

        text = <<~TEXT
          AN ORDINANCE concerning Baltimore City Code.
          BY repealing and re-ordaining, with amendments,
          Article 1 - General Provisions
          Section 4-1
          Baltimore City Code

          SECTION 1. BE IT ORDAINED BY THE MAYOR AND CITY COUNCIL OF BALTIMORE:
          § 4-1 is hereby repealed.
        TEXT

        bill = make_bill(extracted_text: text, sway_locale: baltimore)
        described_class.new(bill: bill).call

        refs = refs_for(bill).to_a
        expect(refs.size).to eq(1)
        expect(refs.first.key).to eq("art_1__sec_4-1")
        expect(refs.first.authoritative).to be(true)
      end
    end

    describe "inverted Maryland citations with decimal section numbers and ASCII hyphens" do
      it "resolves § 21-801.1(b) of the Transportation Article and § 15-1208.1(c) of the Insurance Article without Baltimore short-form false positives" do
        create(:law_section,
          sway_locale: maryland,
          key: "art_gtr__sec_21-801.1",
          article: "gtr",
          section: "21-801.1",
          title: "Article - Transportation § 21-801.1",
          body: "Maximum speed limits.")
        create(:law_section,
          sway_locale: maryland,
          key: "art_gin__sec_15-1208.1",
          article: "gin",
          section: "15-1208.1",
          title: "Article - Insurance § 15-1208.1",
          body: "Special enrollment periods.")

        text = <<~TEXT
          A BILL ENTITLED
          AN ACT concerning Speed Limits and Insurance

          SECTION 1. BE IT ENACTED BY THE GENERAL ASSEMBLY OF MARYLAND, That:
          In § 21-801.1(b) of the Transportation Article and in § 15-1208.1(c) of the Insurance Article,
          the limits are hereby amended.
        TEXT

        bill = make_bill(extracted_text: text, sway_locale: maryland)
        result = described_class.new(bill: bill).call

        refs = refs_for(bill).to_a
        expect(refs.map(&:key)).to eq(%w[art_gtr__sec_21-801.1 art_gin__sec_15-1208.1])
        expect(refs.map(&:article)).to eq(%w[gtr gin])
        expect(refs.map(&:section)).to eq(%w[21-801.1 15-1208.1])
        expect(refs.map(&:resolution)).to eq(%w[exact exact])
        expect(refs.map(&:article)).not_to include("21", "15")
        expect(result.unresolved_keys).to be_empty
      end
    end
  end

  describe "US Congress single-bill parsing" do
    let(:congress) { create(:sway_locale, :congress) }
    let(:baltimore) { create(:sway_locale, :baltimore) }

    it "resolves Title and U.S.C. citations against the US Congress jurisdiction only" do
      us_section = create(:law_section,
        sway_locale: congress,
        key: "art_42__sec_1983",
        article: "42",
        section: "1983",
        title: "Civil action for deprivation of rights")
      # Same key in Baltimore must never be resolved
      create(:law_section,
        sway_locale: baltimore,
        key: "art_42__sec_1983",
        article: "42",
        section: "1983",
        title: "Baltimore decoy section")

      text = <<~TEXT
        A BILL
        To amend title 42, United States Code, and for other purposes.

        Be it enacted by the Senate and House of Representatives of the United States of America in Congress assembled,

        SECTION 1. SHORT TITLE.
        This Act may be cited as the "Civil Rights Enforcement Act".

        SEC. 2. EQUAL RIGHTS UNDER THE LAW.
        Section 1983 of title 42, United States Code, is amended to read as follows:
        Every person who, under color of any statute...
      TEXT

      bill = make_bill(extracted_text: text, sway_locale: congress)
      result = described_class.new(bill: bill).call

      expect(bill.reload.parsing_target).to eq("code")
      expect(result.no_sections_found).to be(false)

      refs = refs_for(bill).to_a
      expect(refs.size).to eq(1)
      ref = refs.first
      expect(ref.article).to eq("42")
      expect(ref.section).to eq("1983")
      expect(ref.resolution).to eq("exact")
      expect(ops_for(bill).first.target_law_section_id).to eq(us_section.id)
    end

    it "recognizes standard U.S.C. cite format (42 U.S.C. 1983)" do
      create(:law_section,
        sway_locale: congress,
        key: "art_42__sec_1983",
        article: "42",
        section: "1983",
        title: "Civil action for deprivation of rights")

      text = "This amends 42 U.S.C. 1983 to provide additional remedies."
      bill = make_bill(extracted_text: text, sway_locale: congress)
      result = described_class.new(bill: bill).call

      expect(result.no_sections_found).to be(false)
      ref = refs_for(bill).first
      expect(ref.section).to eq("1983")
      expect(ref.resolution).to eq("exact")
      expect(ref.key).to eq("art_42__sec_1983")
    end

    it "handles a non-amending Congressional resolution cleanly without inventing changes" do
      text = <<~TEXT
        H. RES. 456
        Recognizing the significance of national civic participation day.

        Resolved, That the House of Representatives expresses support for the goals and ideals of civic participation day.
      TEXT

      bill = make_bill(extracted_text: text, sway_locale: congress)
      result = described_class.new(bill: bill).call

      expect(result.no_sections_found).to be(true)
      expect(result.section_reference_ids).to be_empty
      expect(result.operation_ids).to be_empty
      expect(result.amendment_source).to eq("none")
      expect(refs_for(bill)).to be_empty
      expect(ops_for(bill)).to be_empty
    end

    it "fails with a diagnostic error when Congress bill text is genuinely missing" do
      bill = make_bill(extracted_text: nil, sway_locale: congress)
      expect { described_class.new(bill: bill).call }
        .to raise_error(BillProcessingError, /has no extracted_text/)
    end
  end
end
