# frozen_string_literal: true

require "rails_helper"

RSpec.describe AcknowledgeTestimonyCoverageService do
  include TestimonySpecHelpers

  let(:sway_locale) { create(:sway_locale, city: "Baltimore", state: "Maryland", country: "United States") }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:bill) do
    create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      external_id: "HB6301",
      title: "An act concerning acknowledging testimony coverage"
    )
  end
  let(:user) { create(:user) }

  def cleaned_artifact(raw_chars:, cleaned_chars:, letters: [])
    {
      "version" => 1,
      "text" => "C" * cleaned_chars,
      "counts" => {"raw_chars" => raw_chars, "cleaned_chars" => cleaned_chars},
      "letters" => letters,
      "campaign_drafts" => []
    }
  end

  # Named distinctly from coverage_report_spec.rb's own "coverage_letter" —
  # that helper takes a source_kind: keyword, this one always fixes
  # "named_organization"; two same-named bare RSpec helpers with different
  # shapes collide under Steep's sig-test/object_spec_methods.rbs convention.
  def ack_letter(position, offset, characters)
    {
      "position" => position, "character_offset" => offset, "characters" => characters,
      "sender_address" => "sender#{position}@example.com", "sender_domain" => "example.com",
      "source_kind" => "named_organization", "source_evidence" => nil
    }
  end

  describe "#call" do
    it "refuses with :nothing_left_out and stores no row when the report finds nothing to acknowledge" do
      # The letter must span the WHOLE cleaned text — production's
      # LetterSplitter always partitions it fully, so a shorter letter here
      # would leave chars unaccounted for and read as a real coverage gap.
      letters = [ack_letter(0, 0, 900)]
      bill.create_bill_llm_provisioning!(
        extracted_testimony: "R" * 900,
        cleaned_testimony: cleaned_artifact(raw_chars: 900, cleaned_chars: 900, letters: letters),
        cleaned_testimony_at: 1.hour.ago,
        testimony_fetched_at: 2.hours.ago
      )

      outcome = described_class.new(bill: bill, actor: user, digest: current_digest).call

      expect(outcome).to eq(:nothing_left_out)
      expect(TestimonyCoverageAcknowledgement.count).to eq(0)
    end

    it "refuses with :run_in_flight while a clean-testimony run is currently rewriting the numbers" do
      bill.create_bill_llm_provisioning!(extracted_testimony: "R" * (max_chars + 500))
      create(:legislation_pipeline_run, bill: bill, status: "cleaning_testimony")

      outcome = described_class.new(bill: bill, actor: user, digest: "whatever").call

      expect(outcome).to eq(:run_in_flight)
      expect(TestimonyCoverageAcknowledgement.count).to eq(0)
    end

    it "refuses with :digest_mismatch when the digest sent no longer matches the current numbers" do
      bill.create_bill_llm_provisioning!(extracted_testimony: "R" * (max_chars + 500))

      outcome = described_class.new(bill: bill, actor: user, digest: "stale-digest-from-a-different-screen").call

      expect(outcome).to eq(:digest_mismatch)
      expect(TestimonyCoverageAcknowledgement.count).to eq(0)
    end

    it "stores a row tied to the bill, the operator and the digest, and answers :acknowledged" do
      bill.create_bill_llm_provisioning!(extracted_testimony: "R" * (max_chars + 500))
      digest = current_digest

      outcome = described_class.new(bill: bill, actor: user, digest: digest).call

      expect(outcome).to eq(:acknowledged)
      ack = TestimonyCoverageAcknowledgement.sole
      expect(ack.bill).to eq(bill)
      expect(ack.acknowledged_by).to eq(user)
      expect(ack.coverage_digest).to eq(digest)
    end

    it "records which pipeline run produced the acknowledged numbers, when one is known" do
      bill.create_bill_llm_provisioning!(extracted_testimony: "R" * 1_000)
      run = create(:legislation_pipeline_run, :completed)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill.external_id,
        stage_results: {"clean_testimony" => {"status" => "failed", "at" => Time.current.iso8601}})

      outcome = described_class.new(bill: bill, actor: user, digest: current_digest).call

      expect(outcome).to eq(:acknowledged)
      expect(TestimonyCoverageAcknowledgement.sole.legislation_pipeline_run).to eq(run)
    end

    it "acknowledging twice with the same numbers is harmless and leaves one row" do
      bill.create_bill_llm_provisioning!(extracted_testimony: "R" * (max_chars + 500))
      digest = current_digest

      first = described_class.new(bill: bill, actor: user, digest: digest).call
      second = described_class.new(bill: bill, actor: user, digest: digest).call

      expect(first).to eq(:acknowledged)
      expect(second).to eq(:acknowledged)
      expect(TestimonyCoverageAcknowledgement.count).to eq(1)
    end

    it "changing the numbers makes a stored acknowledgement stop matching" do
      bill.create_bill_llm_provisioning!(extracted_testimony: "R" * (max_chars + 5_000))
      described_class.new(bill: bill, actor: user, digest: current_digest).call
      expect(Testimony::CoverageReport.call(bill: bill.reload).acknowledged).to be(true)

      # Re-running the clean-testimony stage writes a fresh artifact with
      # different removed/left-out numbers than the raw split the
      # acknowledgement above was tied to. The letters TILE the bundle, as
      # Testimony::LetterSplitter's own entries do, and there are more of
      # them than the size limit has room for, so the re-run still leaves
      # something out.
      with_app_config(:llm, llm_max_positions_chunks: 1) do
        letters = (0...32).map { |position| ack_letter(position, position * 5_000, 5_000) }
        bill.bill_llm_provisioning.update!(
          cleaned_testimony: cleaned_artifact(raw_chars: max_chars + 5_000, cleaned_chars: 160_000, letters: letters),
          cleaned_testimony_at: Time.current
        )

        result = Testimony::CoverageReport.call(bill: bill.reload)
        expect(result.state).to eq(:cleaned)
        expect(Testimony::CoverageReport.coverage_gap?(result)).to be(true)
        expect(result.acknowledged).to be(false)
      end
    end
  end
end
