# frozen_string_literal: true

require "rails_helper"

RSpec.describe Testimony::CoverageReport do
  include TestimonySpecHelpers

  let(:sway_locale) { create(:sway_locale, city: "Baltimore", state: "Maryland", country: "United States") }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:bill) do
    create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      external_id: "HB6206",
      title: "An act concerning testimony coverage"
    )
  end

  def cleaned_artifact(raw_chars:, cleaned_chars:, letters: [])
    {
      "version" => 1,
      "text" => "C" * cleaned_chars,
      "counts" => {"raw_chars" => raw_chars, "cleaned_chars" => cleaned_chars},
      "letters" => letters,
      "campaign_drafts" => []
    }
  end

  def coverage_letter(position, offset, characters, source_kind: "named_organization")
    {
      "position" => position, "character_offset" => offset, "characters" => characters,
      "sender_address" => "sender#{position}@example.com", "sender_domain" => "example.com",
      "source_kind" => source_kind, "source_evidence" => nil
    }
  end

  # Letters that TILE the cleaned text, the way Testimony::LetterSplitter's
  # own entries do — every character of the bundle belongs to exactly one
  # letter. A fixture whose letters cover a few hundred characters of a
  # 155,000-character bundle describes no artifact this stage can produce,
  # and it is what let CR-01 hide: the prompt builder rebuilds the bundle
  # letter by letter, so what reaches the model depends on the letters, not
  # on the bundle's own length.
  def tiling_letters(count, characters, source_kind: "named_organization")
    (0...count).map { |position| coverage_letter(position, position * characters, characters, source_kind: source_kind) }
  end

  # W-11: one character per letter, at the FIRST position of that letter's
  # body, drawn from a range no heading or separator can contain. A marker
  # survives the prompt's cut exactly when one character of its letter's body
  # does, which is the rule the code counts by — a heading can survive with
  # none of its body behind it, which is how the old heading-scan and the
  # code disagreed without any example going red.
  def letter_marker(position)
    (0x4E00 + position).chr(Encoding::UTF_8)
  end

  def marked_tiling_text(count, characters)
    (0...count).map { |position| letter_marker(position) + ("C" * (characters - 1)) }.join
  end

  describe "the record bar's arithmetic" do
    it "sums reached + removed + left out to the total, in characters, when the cap binds" do
      bill.create_bill_llm_provisioning!(
        extracted_testimony: "R" * (max_chars + 20_000),
        cleaned_testimony: cleaned_artifact(raw_chars: max_chars + 20_000, cleaned_chars: max_chars + 5_000),
        cleaned_testimony_at: 1.hour.ago,
        testimony_fetched_at: 2.hours.ago
      )

      result = described_class.call(bill: bill)

      expect(result.reached_chars + result.removed_chars + result.left_out_chars).to eq(result.total_chars)
      expect(result.reached_chars).to eq(max_chars)
      expect(result.left_out_chars).to eq(5_000)
      expect(result.removed_chars).to eq(15_000)
    end

    it "sums reached + removed + left out to the total, in characters, when nothing was cut" do
      bill.create_bill_llm_provisioning!(
        extracted_testimony: "R" * 900_000,
        cleaned_testimony: cleaned_artifact(raw_chars: 900_000, cleaned_chars: 40_000),
        cleaned_testimony_at: 1.hour.ago,
        testimony_fetched_at: 2.hours.ago
      )

      result = described_class.call(bill: bill)

      expect(result.reached_chars + result.removed_chars + result.left_out_chars).to eq(result.total_chars)
      expect(result.left_out_chars).to eq(0)
      expect(result.removed_chars).to eq(860_000)
    end

    it "reports repair growth as its own non-negative number when cleaning adds more than it removes" do
      bill.create_bill_llm_provisioning!(
        extracted_testimony: "R" * 140_000,
        cleaned_testimony: cleaned_artifact(raw_chars: 140_000, cleaned_chars: 144_231),
        cleaned_testimony_at: 1.hour.ago,
        testimony_fetched_at: 2.hours.ago
      )

      result = described_class.call(bill: bill)

      expect(result.removed_chars).to eq(0)
      expect(result.repair_added_chars).to eq(4_231)
      expect(result.total_chars).to eq(140_000)
    end

    it "sums reached + left out to the total, in letters — removed_letters is always 0" do
      with_app_config(:llm, llm_max_positions_chunks: 1) do
        letters = tiling_letters(32, 5_000)
        bill.create_bill_llm_provisioning!(
          extracted_testimony: "R" * (max_chars + 25_000),
          cleaned_testimony: cleaned_artifact(raw_chars: max_chars + 25_000, cleaned_chars: 160_000, letters: letters),
          cleaned_testimony_at: 1.hour.ago,
          testimony_fetched_at: 2.hours.ago
        )

        result = described_class.call(bill: bill)

        expect(result.removed_letters).to eq(0)
        expect(result.reached_letters + result.removed_letters + result.left_out_letters).to eq(result.total_letters)
        expect(result.total_letters).to eq(32)
        expect(result.reached_letters).to be < 32
      end
    end

    it "reaches all letters across multi-chunk payloads under default settings" do
      letters = tiling_letters(32, 5_000)
      bill.create_bill_llm_provisioning!(
        extracted_testimony: "R" * (max_chars + 25_000),
        cleaned_testimony: cleaned_artifact(raw_chars: max_chars + 25_000, cleaned_chars: 160_000, letters: letters),
        cleaned_testimony_at: 1.hour.ago,
        testimony_fetched_at: 2.hours.ago
      )

      result = described_class.call(bill: bill)

      expect(result.total_letters).to eq(32)
      expect(result.reached_letters).to eq(32)
      expect(result.left_out_letters).to eq(0)
      expect(result.left_out_chars).to eq(0)
      expect(described_class.coverage_gap?(result)).to be(false)
    end
  end

  # CR-01/WR-09. Every example above measures Testimony::CoverageReport
  # against itself. This one measures it against the thing it is describing:
  # the prompt the model is actually sent. The cleaned bundle here is 300
  # characters UNDER the size limit, so the old arithmetic read "nothing was
  # left out" — while the prompt builder, which rebuilds the bundle letter by
  # letter with a ~106-character heading on each, went 6,000 characters over
  # it and dropped the tail.
  describe "agreement with the prompt the model is actually sent" do
    let(:letter_characters) { 2_495 }
    let(:letter_count) { 60 }

    before do
      cleaned_chars = letter_count * letter_characters # 149,700 — under the limit
      bill.create_bill_llm_provisioning!(
        extracted_testimony: "R" * cleaned_chars,
        cleaned_testimony: cleaned_artifact(
          raw_chars: cleaned_chars, cleaned_chars: cleaned_chars,
          letters: tiling_letters(letter_count, letter_characters)
        ).merge("text" => marked_tiling_text(letter_count, letter_characters)),
        cleaned_testimony_at: 1.hour.ago,
        testimony_fetched_at: 2.hours.ago
      )
    end

    def letters_in_the_prompt
      message = BillPositionsPromptBuilder.new(bill).user_message
      (0...letter_count).count { |position| message.include?(letter_marker(position)) }
    end

    context "when single-chunk prompt is forced (llm_max_positions_chunks: 1)" do
      around { |example| with_app_config(:llm, llm_max_positions_chunks: 1, &example) }

      it "reports exactly the letters the prompt carries, not the letters the bundle length allows" do
        result = described_class.call(bill: bill)

        expect(result.total_letters).to eq(letter_count)
        expect(letters_in_the_prompt).to be < letter_count
        expect(result.reached_letters).to eq(letters_in_the_prompt)
        expect(result.left_out_letters).to be > 0
      end

      it "requires an acknowledgement, because letters really did not reach the model" do
        result = described_class.call(bill: bill)

        expect(described_class.coverage_gap?(result)).to be(true)
      end

      it "reports fewer characters reached than the cleaned bundle holds" do
        result = described_class.call(bill: bill)

        expect(result.reached_chars).to be < result.total_chars
        expect(result.left_out_chars).to be > 0
        expect(result.reached_chars + result.removed_chars + result.left_out_chars).to eq(result.total_chars)
      end

      context "when the cut falls between a letter's heading and its first body character" do
        let(:letter_characters) { 395 }
        let(:letter_count) { 300 }

        it "does not count a letter whose heading survived but whose body did not" do
          message = BillPositionsPromptBuilder.new(bill).user_message
          headings = message.scan(BillPositionsPromptBuilder::NAMEABLE_LETTER_HEADING).length
          result = described_class.call(bill: bill)

          expect(headings).to eq(letters_in_the_prompt + 1)
          expect(result.reached_letters).to eq(letters_in_the_prompt)
        end
      end
    end

    context "under default multi-chunk partitioning" do
      it "reaches all letters across chunked payloads with zero coverage gap" do
        result = described_class.call(bill: bill)

        expect(result.total_letters).to eq(letter_count)
        expect(result.reached_letters).to eq(letter_count)
        expect(result.left_out_letters).to eq(0)
        expect(result.left_out_chars).to eq(0)
        expect(described_class.coverage_gap?(result)).to be(false)
      end
    end
  end

  # W-11's other half: the :with_testimony trait always reported a closed gate,
  # so no spec built on it could tell a working gate from a broken one.
  describe "the :with_testimony factory trait" do
    it "reports no gap by default, which is what its callers rely on" do
      provisioning = create(:bill_llm_provisioning, :with_testimony, bill: bill)

      result = described_class.call(bill: bill, provisioning: provisioning)

      expect(described_class.coverage_gap?(result)).to be(false)
    end

    it "reports a real gap when one is asked for" do
      provisioning = create(:bill_llm_provisioning, :with_testimony, bill: bill, testimony_gap_chars: 5_000)

      result = described_class.call(bill: bill, provisioning: provisioning)

      expect(result.left_out_chars).to be > 0
      expect(described_class.coverage_gap?(result)).to be(true)
    end
  end

  # When Llm::Client.build fails, every letter the rules read as
  # an organization's own voice is rewritten to the safe kind, and approving
  # that organization is then refused with nothing on screen saying why.
  describe "the model-fallback letter count" do
    it "reports the count the cleaning stage recorded" do
      artifact = cleaned_artifact(raw_chars: 1_000, cleaned_chars: 900)
      artifact["counts"]["source_kind_model_fallbacks"] = 7
      bill.create_bill_llm_provisioning!(
        extracted_testimony: "R" * 1_000, cleaned_testimony: artifact,
        cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago
      )

      expect(described_class.call(bill: bill).model_fallback_letter_count).to eq(7)
    end

    it "reports nil when no fresh cleaned artifact exists to have counted" do
      bill.create_bill_llm_provisioning!(extracted_testimony: "R" * 1_000)

      expect(described_class.call(bill: bill).model_fallback_letter_count).to be_nil
    end

    it "leaves the acknowledgement digest alone, since it names no number that was cut" do
      artifact = cleaned_artifact(raw_chars: 1_000, cleaned_chars: 900)
      bill.create_bill_llm_provisioning!(
        extracted_testimony: "R" * 1_000, cleaned_testimony: artifact,
        cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago
      )
      without_fallbacks = described_class.call(bill: bill).digest

      artifact["counts"]["source_kind_model_fallbacks"] = 7
      bill.bill_llm_provisioning.update!(cleaned_testimony: artifact)

      expect(described_class.call(bill: bill.reload).digest).to eq(without_fallbacks)
    end
  end

  # Additive only, so total_letters/reached_letters/left_out_letters
  # keep summing the way Result's own comment documents — repeats stay
  # counted in all three, this field only names how many of them there are.
  # @lat: [[testimony-duplicate-letter-marking#Why the coverage report's letter totals were left alone]]
  describe "the repeat letter count" do
    it "reports the stage's own recorded count, without changing total_letters" do
      letters = tiling_letters(3, 100)
      letters[2] = letters[2].merge("repeat" => true)
      artifact = cleaned_artifact(raw_chars: 300, cleaned_chars: 300, letters: letters)
      artifact["counts"]["repeat_letters"] = 1
      bill.create_bill_llm_provisioning!(
        extracted_testimony: "R" * 300, cleaned_testimony: artifact,
        cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago
      )

      result = described_class.call(bill: bill)

      expect(result.repeat_letter_count).to eq(1)
      expect(result.total_letters).to eq(3)
    end

    it "reports no coverage gap when constituent self-letters and repeats fit alongside nameable letters" do
      letters = tiling_letters(4, 100)
      letters[1] = letters[1].merge("source_kind" => "person_speaking_for_self")
      letters[2] = letters[2].merge("repeat" => true, "repeat_of_position" => 0)
      artifact = cleaned_artifact(raw_chars: 400, cleaned_chars: 400, letters: letters)
      bill.create_bill_llm_provisioning!(
        extracted_testimony: "R" * 400,
        cleaned_testimony: artifact,
        cleaned_testimony_at: 1.hour.ago,
        testimony_fetched_at: 2.hours.ago
      )

      result = described_class.call(bill: bill)

      expect(result.left_out_letters).to eq(0)
      expect(result.left_out_chars).to eq(0)
      expect(described_class.coverage_gap?(result)).to be(false)
    end

    it "reports nil when no fresh cleaned artifact exists to have counted" do
      bill.create_bill_llm_provisioning!(extracted_testimony: "R" * 1_000)

      expect(described_class.call(bill: bill).repeat_letter_count).to be_nil
    end

    # A fresh artifact cleaned before Testimony::DuplicateLetterMarker
    # existed carries letters with no "repeat" key and no "repeat_letters" in
    # its counts — this must read as "never measured", not as "measured,
    # zero repeats".
    it "reports nil for a fresh artifact whose counts predate the duplicate-letter step" do
      artifact = cleaned_artifact(raw_chars: 300, cleaned_chars: 300, letters: tiling_letters(3, 100))
      bill.create_bill_llm_provisioning!(
        extracted_testimony: "R" * 300, cleaned_testimony: artifact,
        cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago
      )

      expect(described_class.call(bill: bill).repeat_letter_count).to be_nil
    end
  end

  describe "the six states" do
    it "cleaned: a fresh artifact reports state :cleaned" do
      bill.create_bill_llm_provisioning!(
        extracted_testimony: "R" * 1_000,
        cleaned_testimony: cleaned_artifact(raw_chars: 1_000, cleaned_chars: 900),
        cleaned_testimony_at: 1.hour.ago,
        testimony_fetched_at: 2.hours.ago
      )

      expect(described_class.call(bill: bill).state).to eq(:cleaned)
    end

    it "never-run: no artifact and no recorded stage attempt reports the raw split, removed at zero" do
      bill.create_bill_llm_provisioning!(extracted_testimony: "R" * (max_chars + 500))

      result = described_class.call(bill: bill)

      expect(result.state).to eq(:never_run)
      expect(result.removed_chars).to eq(0)
      expect(result.reached_chars).to eq(max_chars)
      expect(result.left_out_chars).to eq(500)
      expect(result.total_chars).to eq(max_chars + 500)
    end

    it "failed: the last recorded clean-testimony attempt failed, with no prior artifact — raw split, state :failed" do
      bill.create_bill_llm_provisioning!(extracted_testimony: "R" * 1_000)
      run = create(:legislation_pipeline_run, :completed)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill.external_id,
        stage_results: {"clean_testimony" => {"status" => "failed", "at" => Time.current.iso8601}})

      result = described_class.call(bill: bill)

      expect(result.state).to eq(:failed)
      expect(result.total_chars).to eq(1_000)
    end

    it "W-13: another locale's bill with the same external_id cannot report this bill's stage as failed" do
      other_locale = create(:sway_locale, city: "Annapolis", state: "Maryland", country: "United States")
      create(:bill, sway_locale: other_locale,
        legislator: create(:legislator, district: create(:district, sway_locale: other_locale)),
        external_id: bill.external_id, title: "A different jurisdiction's bill of the same number")
      bill.create_bill_llm_provisioning!(extracted_testimony: "R" * 1_000)
      run = create(:legislation_pipeline_run, :completed)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill.external_id,
        stage_results: {"clean_testimony" => {"status" => "failed", "at" => Time.current.iso8601}})

      expect(described_class.call(bill: bill).state).to eq(:never_run)
    end

    it "W-13: a run naming this bill still reports, even when another locale shares the external_id" do
      other_locale = create(:sway_locale, city: "Annapolis", state: "Maryland", country: "United States")
      create(:bill, sway_locale: other_locale,
        legislator: create(:legislator, district: create(:district, sway_locale: other_locale)),
        external_id: bill.external_id, title: "A different jurisdiction's bill of the same number")
      bill.create_bill_llm_provisioning!(extracted_testimony: "R" * 1_000)
      run = create(:legislation_pipeline_run, :completed, bill: bill)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill.external_id,
        stage_results: {"clean_testimony" => {"status" => "failed", "at" => Time.current.iso8601}})

      expect(described_class.call(bill: bill).state).to eq(:failed)
    end

    it "failed: an older successful artifact exists — its numbers are reported, state :failed (not :cleaned)" do
      bill.create_bill_llm_provisioning!(
        extracted_testimony: "R" * 1_000,
        cleaned_testimony: cleaned_artifact(raw_chars: 1_000, cleaned_chars: 900),
        cleaned_testimony_at: 2.hours.ago,
        testimony_fetched_at: 3.hours.ago
      )
      run = create(:legislation_pipeline_run, :completed)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill.external_id,
        stage_results: {"clean_testimony" => {"status" => "failed", "at" => 1.hour.ago.iso8601}})

      result = described_class.call(bill: bill)

      expect(result.state).to eq(:failed)
      expect(result.total_chars).to eq(1_000)
      expect(result.reached_chars + result.removed_chars + result.left_out_chars).to eq(result.total_chars)
    end

    it "running: an active run currently executing the clean-testimony stage reports state :running" do
      bill.create_bill_llm_provisioning!(extracted_testimony: "R" * 1_000)
      create(:legislation_pipeline_run, bill: bill, status: "cleaning_testimony")

      expect(described_class.call(bill: bill).state).to eq(:running)
    end

    it "running takes priority over a fresh artifact — the artifact's numbers are shown as the last run's" do
      bill.create_bill_llm_provisioning!(
        extracted_testimony: "R" * 1_000,
        cleaned_testimony: cleaned_artifact(raw_chars: 1_000, cleaned_chars: 900),
        cleaned_testimony_at: 1.hour.ago,
        testimony_fetched_at: 2.hours.ago
      )
      create(:legislation_pipeline_run, bill: bill, status: "cleaning_testimony")

      result = described_class.call(bill: bill)

      expect(result.state).to eq(:running)
      expect(result.total_chars).to eq(1_000)
    end

    it "no testimony: a blank raw column and no artifact renders no notice — every count is zero" do
      bill.create_bill_llm_provisioning!(extracted_testimony: nil)

      result = described_class.call(bill: bill)

      expect(result.state).to eq(:no_testimony)
      expect(result.total_chars).to eq(0)
      expect(result.reached_chars).to eq(0)
      expect(result.removed_chars).to eq(0)
      expect(result.left_out_chars).to eq(0)
    end

    # A fetch AFTER the last clean-testimony run supersedes the artifact.
    # Every other example in this file sets cleaned_testimony_at after
    # testimony_fetched_at (fresh) — this is the one that does not.
    it "stale: an artifact older than the last fetch reports :stale, the live raw split, and no letter counts" do
      letters = tiling_letters(4, 900)
      bill.create_bill_llm_provisioning!(
        extracted_testimony: "R" * (max_chars + 20_000),
        cleaned_testimony: cleaned_artifact(raw_chars: 1_000, cleaned_chars: 900, letters: letters),
        cleaned_testimony_at: 2.hours.ago,
        testimony_fetched_at: 1.hour.ago
      )

      result = described_class.call(bill: bill)

      expect(result.state).to eq(:stale)
      expect(described_class.coverage_gap?(result)).to be(true)
      expect(result.reached_chars + result.removed_chars + result.left_out_chars).to eq(result.total_chars)
      expect(result.removed_chars).to eq(0)
      expect(result.total_letters).to be_nil
      expect(result.reached_letters).to be_nil
      expect(result.left_out_letters).to be_nil
      expect(result.individual_letter_count).to be_nil
    end

    # A letter counts as "reached" the moment ONE of its own characters
    # lands inside the budget, so a single letter spanning the whole cleaned
    # bundle can leave most of itself out while reading as fully reached.
    it "reports a coverage gap when a single unsplit letter is only partially reached" do
      cleaned_chars = max_chars + 5_000
      letters = [coverage_letter(0, 0, cleaned_chars)]
      bill.create_bill_llm_provisioning!(
        extracted_testimony: "R" * (cleaned_chars + 10_000),
        cleaned_testimony: cleaned_artifact(raw_chars: cleaned_chars + 10_000, cleaned_chars: cleaned_chars, letters: letters),
        cleaned_testimony_at: 1.hour.ago,
        testimony_fetched_at: 2.hours.ago
      )

      result = described_class.call(bill: bill)

      expect(result.left_out_letters).to eq(0)
      expect(result.left_out_chars).to be > 0
      expect(described_class.coverage_gap?(result)).to be(true)
    end

    # A paste-only bill — the exact remedy FetchHearingsService tells an
    # operator to use when extraction fails — must not report :no_testimony,
    # or the whole coverage report (and its gate) disappears. It must also
    # not carry :never_run's own always-a-gap rule: that rule exists because
    # RAW extraction sits uncleaned, and here there is none — the paste is
    # never cleaned at all, so nothing was left for a stage to miss.
    it "paste-only: no extracted testimony and a substantive paste reports :never_run, not :no_testimony, with no gap" do
      bill.create_bill_llm_provisioning!(extracted_testimony: nil, supplemental_testimony: "P" * 5_000)

      result = described_class.call(bill: bill)

      expect(result.state).not_to eq(:no_testimony)
      expect(result.state).to eq(:never_run)
      expect(result.total_chars).to eq(5_000)
      expect(result.left_out_chars).to eq(0)
      expect(described_class.coverage_gap?(result)).to be(false)
    end

    it "paste-only, oversized: a paste alone bigger than MAX_TESTIMONY_CHARS reports a real cut" do
      bill.create_bill_llm_provisioning!(extracted_testimony: nil, supplemental_testimony: "P" * (max_chars + 2_000))

      result = described_class.call(bill: bill)

      expect(result.state).to eq(:never_run)
      expect(result.left_out_chars).to be > 0
    end
  end

  describe "the paste — current with no stage re-run" do
    it "changes reached/left-out numbers the moment the paste changes, without touching the cleaned artifact" do
      with_app_config(:llm, llm_max_positions_chunks: 1) do
        letters = tiling_letters(32, 5_000)
        bill.create_bill_llm_provisioning!(
          extracted_testimony: "R" * 160_000,
          cleaned_testimony: cleaned_artifact(raw_chars: 160_000, cleaned_chars: 160_000, letters: letters),
          cleaned_testimony_at: 1.hour.ago,
          testimony_fetched_at: 2.hours.ago
        )
        provisioning = bill.bill_llm_provisioning #: BillLlmProvisioning
        cleaned_at_before = provisioning.cleaned_testimony_at

        before_paste = described_class.call(bill: bill.reload)
        expect(before_paste.paste_present).to be(false)
        expect(before_paste.left_out_chars).to be > 0

        provisioning.update!(supplemental_testimony: "P" * 6_000)
        after_paste = described_class.call(bill: bill.reload)

        expect(after_paste.paste_present).to be(true)
        expect(after_paste.paste_chars).to eq(6_000)
        expect(after_paste.left_out_chars).to be > before_paste.left_out_chars
        expect(after_paste.reached_letters).to be < before_paste.reached_letters
        expect(after_paste.displaced_letter_count).to eq(after_paste.left_out_letters)
        expect(provisioning.reload.cleaned_testimony_at).to eq(cleaned_at_before)
      end
    end

    it "ships no paste numbers (nil, not zero) when there is no paste" do
      bill.create_bill_llm_provisioning!(extracted_testimony: "R" * 1_000)

      result = described_class.call(bill: bill)

      expect(result.paste_present).to be(false)
      expect(result.paste_share_of_limit).to be_nil
      expect(result.displaced_letter_count).to eq(0)
    end
  end

  describe "an attachment cut at the per-attachment cap" do
    it "reports the cut and names the cap" do
      bill.create_bill_llm_provisioning!(
        extracted_testimony: "R" * 1_000,
        testimony_attachments: [
          {
            "filename" => "big-attachment.pdf", "attachment_id" => "1",
            "download_status" => "succeeded", "extraction_status" => "succeeded",
            "error" => "extracted text truncated to 500000 chars (was 723456)"
          },
          {
            "filename" => "small-attachment.pdf", "attachment_id" => "2",
            "download_status" => "succeeded", "extraction_status" => "succeeded",
            "error" => nil
          }
        ]
      )

      result = described_class.call(bill: bill)

      expect(result.attachment_cut_count).to eq(1)
      expect(result.attachment_cut_cap).to eq(FetchHearingsService::MAX_ATTACHMENT_TEXT_CHARS)
    end

    it "reports no cut and a nil cap when nothing was clipped" do
      bill.create_bill_llm_provisioning!(extracted_testimony: "R" * 1_000, testimony_attachments: [])

      result = described_class.call(bill: bill)

      expect(result.attachment_cut_count).to eq(0)
      expect(result.attachment_cut_cap).to be_nil
    end
  end

  it "reports zero individuals and nil letter counts when there is no cleaned artifact at all" do
    bill.create_bill_llm_provisioning!(extracted_testimony: "R" * 1_000)

    result = described_class.call(bill: bill)

    expect(result.individual_letter_count).to be_nil
    expect(result.total_letters).to be_nil
  end

  it "counts letters read as individuals speaking for themselves" do
    letters = [
      coverage_letter(0, 0, 100, source_kind: "person_speaking_for_self"),
      coverage_letter(1, 200, 100, source_kind: "named_organization")
    ]
    bill.create_bill_llm_provisioning!(
      extracted_testimony: "R" * 1_000,
      cleaned_testimony: cleaned_artifact(raw_chars: 1_000, cleaned_chars: 900, letters: letters),
      cleaned_testimony_at: 1.hour.ago,
      testimony_fetched_at: 2.hours.ago
    )

    expect(described_class.call(bill: bill).individual_letter_count).to eq(1)
  end

  describe "the digest" do
    it "differs between :never_run and :failed even when every other number matches" do
      never_run_bill = bill
      never_run_bill.create_bill_llm_provisioning!(extracted_testimony: "R" * 1_000)

      failed_bill = create(
        :bill,
        sway_locale: sway_locale,
        legislator: legislator,
        external_id: "HB6207",
        title: "An act concerning testimony coverage, failed run",
        scheduled_release_date_utc: 2.days.ago
      )
      failed_bill.create_bill_llm_provisioning!(extracted_testimony: "R" * 1_000)
      run = create(:legislation_pipeline_run, :completed)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: failed_bill.external_id,
        stage_results: {"clean_testimony" => {"status" => "failed", "at" => Time.current.iso8601}})

      never_run_result = described_class.call(bill: never_run_bill)
      failed_result = described_class.call(bill: failed_bill)

      expect(never_run_result.state).to eq(:never_run)
      expect(failed_result.state).to eq(:failed)
      expect(never_run_result.total_chars).to eq(failed_result.total_chars)
      expect(never_run_result.reached_chars).to eq(failed_result.reached_chars)
      expect(never_run_result.removed_chars).to eq(failed_result.removed_chars)
      expect(never_run_result.left_out_chars).to eq(failed_result.left_out_chars)
      expect(never_run_result.digest).not_to eq(failed_result.digest)
    end
  end
end
