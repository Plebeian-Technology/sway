# frozen_string_literal: true

require "rails_helper"
require "tmpdir"
require "fileutils"

# @lat: [[pipeline-artifact-presence-overview#The batched lookup]]
RSpec.describe Pipeline::ArtifactPresence, type: :model do
  let(:tmp_root) { Pathname.new(Dir.mktmpdir("artifact_presence_spec")) }

  # @lat: [[legislation-path-root-resolution#Why artifact_presence_spec.rb points Rails.root at a temp directory explicitly#Why the spec forces several model classes to load before faking Rails.root]]
  before(:all) do
    [Bill, Legislator, LawSection, BillSectionReference, BillLlmProvisioning, SwayLocale::JurisdictionRulesRegistry].each(&:name)
  end

  # @lat: [[legislation-path-root-resolution#Why artifact_presence_spec.rb points Rails.root at a temp directory explicitly]]
  around do |example|
    with_app_config(:legislation, legislation_root: tmp_root.join("legislation").to_s) { example.run }
  ensure
    FileUtils.remove_entry(tmp_root) if tmp_root.exist?
  end

  before do
    allow(Rails).to receive(:root).and_return(tmp_root)
  end

  context "for fetch-bills" do
    let(:bill) { create(:bill) }

    it "returns true when the Bill row + PDF artifact both exist" do
      pdf_dir = tmp_root.join("legislation/bills/raw/#{bill.sway_locale.name}/#{bill.external_id}")
      pdf_dir.mkpath
      File.write(pdf_dir.join("primary.pdf"), "fake pdf")
      expect(described_class.present?("fetch-bills", bill: bill)).to eq(true)
    end

    it "returns false when no PDF exists on disk" do
      expect(described_class.present?("fetch-bills", bill: bill)).to eq(false)
    end

    it "returns false when bill is nil" do
      expect(described_class.present?("fetch-bills", bill: nil)).to eq(false)
    end
  end

  context "for fetch-law" do
    let(:baltimore) { create(:sway_locale, :baltimore) }
    let(:maryland) { create(:sway_locale, :maryland) }

    # @lat: [[legislation-pipeline#Law artifact readiness]]
    it "returns true when Baltimore root section_index.json + Baltimore LawSection row both exist" do
      law_dir = tmp_root.join("legislation/law")
      law_dir.mkpath
      File.write(law_dir.join("section_index.json"), "[]")
      create(:law_section, sway_locale: baltimore)
      expect(described_class.present?("fetch-law", sway_locale: baltimore)).to eq(true)
    end

    # @lat: [[legislation-pipeline#Law artifact readiness]]
    it "returns false for Maryland when only Baltimore root section_index.json and Baltimore LawSection exist" do
      law_dir = tmp_root.join("legislation/law")
      law_dir.mkpath
      File.write(law_dir.join("section_index.json"), "[]")
      create(:law_section, sway_locale: baltimore)
      expect(described_class.present?("fetch-law", sway_locale: maryland)).to eq(false)
    end

    # @lat: [[legislation-pipeline#Law artifact readiness]]
    it "returns true for Maryland when scoped section_index.json and Maryland LawSection both exist" do
      md_law_dir = tmp_root.join("legislation/law/#{maryland.name}")
      md_law_dir.mkpath
      File.write(md_law_dir.join("section_index.json"), "[]")
      create(:law_section, sway_locale: maryland)
      expect(described_class.present?("fetch-law", sway_locale: maryland)).to eq(true)
    end

    it "returns false when section_index.json is missing" do
      create(:law_section, sway_locale: baltimore)
      expect(described_class.present?("fetch-law", sway_locale: baltimore)).to eq(false)
    end

    it "returns false when no LawSection row exists for the locale" do
      law_dir = tmp_root.join("legislation/law")
      law_dir.mkpath
      File.write(law_dir.join("section_index.json"), "[]")
      expect(described_class.present?("fetch-law", sway_locale: baltimore)).to eq(false)
    end

    it "returns false when neither bill nor sway_locale is supplied" do
      law_dir = tmp_root.join("legislation/law")
      law_dir.mkpath
      File.write(law_dir.join("section_index.json"), "[]")
      create(:law_section, sway_locale: baltimore)
      expect(described_class.present?("fetch-law")).to eq(false)
    end

    it "resolves sway_locale from bill when bill is supplied" do
      law_dir = tmp_root.join("legislation/law")
      law_dir.mkpath
      File.write(law_dir.join("section_index.json"), "[]")
      create(:law_section, sway_locale: baltimore)
      bill = create(:bill, sway_locale: baltimore)
      expect(described_class.present?("fetch-law", bill: bill)).to eq(true)
    end
  end

  context "for extract-text" do
    it "returns true when bill.extracted_text is populated" do
      bill = create(:bill, extracted_text: "section 1 …")
      expect(described_class.present?("extract-text", bill: bill)).to eq(true)
    end

    it "returns false when bill.extracted_text is blank" do
      bill = create(:bill, extracted_text: nil)
      expect(described_class.present?("extract-text", bill: bill)).to eq(false)
    end

    it "returns false when bill is nil" do
      expect(described_class.present?("extract-text", bill: nil)).to eq(false)
    end
  end

  context "for parse-sections" do
    it "returns true when a BillSectionReference row exists for the bill" do
      bill = create(:bill)
      create(:bill_section_reference, bill: bill)
      expect(described_class.present?("parse-sections", bill: bill)).to eq(true)
    end

    it "returns false when no BillSectionReference rows exist for the bill" do
      bill = create(:bill)
      expect(described_class.present?("parse-sections", bill: bill)).to eq(false)
    end

    it "returns false when bill is nil" do
      expect(described_class.present?("parse-sections", bill: nil)).to eq(false)
    end

    # @lat: [[pipeline-artifact-presence-overview#Why parse-sections has a secondary signal]]
    context "stage_results not-applicable signal" do
      it "returns true when a prior pipeline_run_bill recorded parse_sections succeeded with zero refs" do
        bill = create(:bill)
        create(:pipeline_run_bill,
          bill_external_id: bill.external_id,
          stage_results: {"parse_sections" => {"status" => "succeeded", "at" => "2026-05-26T00:00:00Z"}})

        expect(::BillSectionReference.exists?(bill_id: bill.id)).to eq(false) # no rows at all
        expect(described_class.present?("parse-sections", bill: bill)).to eq(true)
      end

      it "returns true when parse_sections was skipped (artifact_present skip)" do
        bill = create(:bill)
        create(:pipeline_run_bill,
          bill_external_id: bill.external_id,
          stage_results: {"parse_sections" => {"status" => "skipped", "reason" => "artifact_present"}})

        expect(described_class.present?("parse-sections", bill: bill)).to eq(true)
      end

      it "returns false when parse_sections.status is failed (real defect, not not-applicable)" do
        bill = create(:bill)
        create(:pipeline_run_bill,
          bill_external_id: bill.external_id,
          stage_results: {"parse_sections" => {"status" => "failed", "error" => "boom"}})

        expect(described_class.present?("parse-sections", bill: bill)).to eq(false)
      end

      it "returns false when bill has no pipeline_run_bill history AND no references" do
        bill = create(:bill)
        expect(described_class.present?("parse-sections", bill: bill)).to eq(false)
      end

      it "prefers affirmative artifact (BillSectionReference) over stage_results check" do
        bill = create(:bill)
        create(:bill_section_reference, bill: bill)
        # The run recorded nothing, but real section rows exist, and real rows win.
        expect(described_class.present?("parse-sections", bill: bill)).to eq(true)
      end
    end
  end

  context "for generate-diffs" do
    it "returns true when bill_llm_provisioning&.diff_content is present" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill, diff_content: "## diff")
      expect(described_class.present?("generate-diffs", bill: bill.reload)).to eq(true)
    end

    it "returns false when no bill_llm_provisioning exists" do
      bill = create(:bill)
      expect(described_class.present?("generate-diffs", bill: bill)).to eq(false)
    end

    it "returns false when diff_content is blank" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill, diff_content: nil)
      expect(described_class.present?("generate-diffs", bill: bill.reload)).to eq(false)
    end

    it "returns false when bill is nil" do
      expect(described_class.present?("generate-diffs", bill: nil)).to eq(false)
    end
  end

  context "for fetch-hearings" do
    # @lat: [[legislation-path-segment-safety#Segment validation]]
    it "returns true when legislation/hearings/<sway_locale>/<external_id>.json exists" do
      bill = create(:bill)
      hearings_dir = tmp_root.join("legislation/hearings/#{bill.sway_locale.name}")
      hearings_dir.mkpath
      File.write(hearings_dir.join("#{bill.external_id}.json"), "[]")
      expect(described_class.present?("fetch-hearings", bill: bill)).to eq(true)
    end

    it "returns false when the hearings JSON file is missing" do
      bill = create(:bill)
      expect(described_class.present?("fetch-hearings", bill: bill)).to eq(false)
    end

    it "does NOT consult the nested legislation/bills/hearings path (CONTEXT drift guard)" do
      # Here only the nested folder is filled in and the flat file is missing. If the
      # code ever went back to reading the nested folder, this would wrongly report
      # "present". Only the flat file counts.
      bill = create(:bill)
      nested = tmp_root.join("legislation/bills/hearings/#{bill.sway_locale.name}/#{bill.external_id}")
      nested.mkpath
      File.write(nested.join("hearings.json"), "[]")
      expect(described_class.present?("fetch-hearings", bill: bill)).to eq(false)
    end

    it "returns false when bill is nil" do
      expect(described_class.present?("fetch-hearings", bill: nil)).to eq(false)
    end
  end

  context "for clean-testimony" do
    it "returns true when the cleaned artifact is no older than testimony_fetched_at" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill, cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago)
      expect(described_class.present?("clean-testimony", bill: bill.reload)).to eq(true)
    end

    it "returns false when the cleaned artifact predates testimony_fetched_at (a later fetch replaced it)" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill, cleaned_testimony_at: 2.hours.ago, testimony_fetched_at: 1.hour.ago)
      expect(described_class.present?("clean-testimony", bill: bill.reload)).to eq(false)
    end

    it "returns true when there is no testimony_fetched_at to compare against" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill, cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: nil)
      expect(described_class.present?("clean-testimony", bill: bill.reload)).to eq(true)
    end

    it "returns false when no bill_llm_provisioning exists" do
      bill = create(:bill)
      expect(described_class.present?("clean-testimony", bill: bill)).to eq(false)
    end

    it "returns false when cleaned_testimony_at is blank" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill, cleaned_testimony_at: nil)
      expect(described_class.present?("clean-testimony", bill: bill.reload)).to eq(false)
    end

    it "returns false when bill is nil" do
      expect(described_class.present?("clean-testimony", bill: nil)).to eq(false)
    end
  end

  context "for summarize-bill" do
    it "returns true when bill_llm_provisioning&.llm_summary is present" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill, llm_summary: "## summary")
      expect(described_class.present?("summarize-bill", bill: bill.reload)).to eq(true)
    end

    it "returns false when no bill_llm_provisioning exists" do
      bill = create(:bill)
      expect(described_class.present?("summarize-bill", bill: bill)).to eq(false)
    end

    it "returns false when llm_summary is blank" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill, llm_summary: nil)
      expect(described_class.present?("summarize-bill", bill: bill.reload)).to eq(false)
    end

    it "returns false when bill is nil" do
      expect(described_class.present?("summarize-bill", bill: nil)).to eq(false)
    end
  end

  context "for unknown stage" do
    it "raises ArgumentError with the offending key in the message" do
      bill = create(:bill)
      expect { described_class.present?("totally-bogus", bill: bill) }
        .to raise_error(ArgumentError, /unknown stage_key.*totally-bogus/)
    end
  end

  context "batched accessor batch_for (FINDING-3 perf)" do
    it "returns {} for an empty relation" do
      expect(described_class.batch_for(bills: Bill.none)).to eq({})
    end

    it "returns Hash[external_id => Hash[stage_key => bool]] shaped correctly" do
      bill_a = create(:bill, extracted_text: "x")
      bill_b = create(:bill, extracted_text: nil)
      create(:bill_llm_provisioning, bill: bill_a, llm_summary: "ok", diff_content: nil)
      create(:bill_section_reference, bill: bill_b)

      result = described_class.batch_for(bills: Bill.where(id: [bill_a.id, bill_b.id]))

      expect(result.keys).to match_array([bill_a.external_id, bill_b.external_id])

      # The inner Hash must carry all 7 per-bill stages. fetch-law is left out because
      # it is checked once per run, not once per bill.
      expected_inner_keys = %w[
        fetch-bills
        extract-text
        parse-sections
        generate-diffs
        fetch-hearings
        clean-testimony
        summarize-bill
      ].sort
      result.each_value do |inner|
        expect(inner.keys.sort).to eq(expected_inner_keys)
        inner.each_value { |v| expect(v).to be_in([true, false]) }
      end

      # Bill A has extracted text and a summary, but no section refs and no diff.
      expect(result[bill_a.external_id]["extract-text"]).to eq(true)
      expect(result[bill_a.external_id]["summarize-bill"]).to eq(true)
      expect(result[bill_a.external_id]["parse-sections"]).to eq(false)
      expect(result[bill_a.external_id]["generate-diffs"]).to eq(false)
      # Bill B has no extracted text and one section ref.
      expect(result[bill_b.external_id]["extract-text"]).to eq(false)
      expect(result[bill_b.external_id]["parse-sections"]).to eq(true)
    end

    it "eager-loads bill_llm_provisioning to avoid N+1 (FINDING-3)" do
      bills = create_list(:bill, 3)
      relation = Bill.where(id: bills.map(&:id))
      # batch_for has to load every bill's llm provisioning row up front by calling
      # .includes(:bill_llm_provisioning), instead of one query per bill. This watches
      # for that call.
      expect(relation).to receive(:includes).with(:bill_llm_provisioning).and_call_original
      described_class.batch_for(bills: relation)
    end

    it "matches per-bill present? results (parity lock — single source of truth)" do
      bill = create(:bill, extracted_text: "x")
      create(:bill_llm_provisioning, bill: bill, llm_summary: "yes", diff_content: "yes")
      hearings_dir = tmp_root.join("legislation/hearings/#{bill.sway_locale.name}")
      hearings_dir.mkpath
      File.write(hearings_dir.join("#{bill.external_id}.json"), "[]")
      pdf_dir = tmp_root.join("legislation/bills/raw/#{bill.sway_locale.name}/#{bill.external_id}")
      pdf_dir.mkpath
      File.write(pdf_dir.join("primary.pdf"), "x")

      result = described_class.batch_for(bills: Bill.where(id: bill.id))

      %w[fetch-bills extract-text parse-sections generate-diffs fetch-hearings summarize-bill].each do |stage_key|
        expected = described_class.present?(stage_key, bill: bill.reload)
        expect(result[bill.external_id][stage_key]).to eq(expected),
          "batch_for[#{stage_key}] (#{result[bill.external_id][stage_key].inspect}) does not match present?(#{stage_key}) (#{expected.inspect})"
      end
    end

    # @lat: [[legislation-pipeline-external-id-ambiguity#The ambiguous-id set in batch_for]]
    describe "an external_id held by bills in two locales" do
      def two_locale_collision
        shared = "COLLIDE-1"
        first = create(:bill, external_id: shared, extracted_text: "text on the first")
        second = create(:bill, external_id: shared,
          sway_locale: create(:sway_locale, city: "elsewhere", state: "maryland", country: "united_states"), extracted_text: nil)
        [shared, first, second]
      end

      it "leaves the id out of the map rather than answering for one of them" do
        shared, first, second = two_locale_collision

        result = described_class.batch_for(bills: Bill.where(id: [first.id, second.id]))

        expect(result).not_to have_key(shared)
      end

      it "says why, so the collision is fixable" do
        _shared, first, second = two_locale_collision
        allow(SwayLogging).to receive(:warn)

        described_class.batch_for(bills: Bill.where(id: [first.id, second.id]))

        expect(SwayLogging).to have_received(:warn).with(/matches bills in more than one sway_locale/)
      end

      # Three rows must not fold back into an answer: the third would otherwise
      # write the key the second had just removed.
      it "keeps the id out however many bills share it" do
        shared = "COLLIDE-2"
        bills = 3.times.map do |i|
          create(:bill, external_id: shared,
            sway_locale: create(:sway_locale, city: "place-#{i}", state: "maryland", country: "united_states"), extracted_text: "t")
        end

        result = described_class.batch_for(bills: Bill.where(id: bills.map(&:id)))

        expect(result).not_to have_key(shared)
      end

      # And an id only ONE bill holds still gets its answer.
      it "still answers for an id that is not shared" do
        _shared, first, second = two_locale_collision
        alone = create(:bill, external_id: "ALONE-1", extracted_text: "x")

        result = described_class.batch_for(bills: Bill.where(id: [first.id, second.id, alone.id]))

        expect(result).to have_key("ALONE-1")
      end
    end
  end
end
