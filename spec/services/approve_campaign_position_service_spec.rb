# frozen_string_literal: true

require "rails_helper"

# Approves a collapsed campaign into a stored
# Campaign, matching an existing campaign on the bill or creating a new one
# — and never creating an Organization on the way.
RSpec.describe ApproveCampaignPositionService do
  # A group entry shaped like Testimony::CampaignMarker's own output —
  # everything TestimonyCampaignDraftResource and this service both read.
  # Named distinctly from other spec files' own group-shaped helpers (e.g.
  # campaign_marker_spec.rb's "letter") so Steep's sig-test shims never see
  # two different shapes under one name.
  def campaign_group(id:, sender_count: 3, letter_count: 3)
    {
      "id" => id, "letter_positions" => [], "shared_text" => "shared template line",
      "sender_count" => sender_count, "letter_count" => letter_count,
      "added_words" => "", "senders_added_words_left_out" => 0
    }
  end

  # A letter entry. offset and characters together are how a fixture builds
  # letters that TILE the cleaned bundle, which is what
  # Testimony::LetterSplitter really produces and what
  # BillPositionsPromptBuilder rebuilds the prompt from — a fixture whose
  # letters cover a few characters of a 150,000-character bundle reports a
  # cut the prompt does not make (CR-01).
  def campaign_letter(position, offset, characters = 10)
    {
      "position" => position, "character_offset" => offset, "characters" => characters,
      "sender_address" => nil, "sender_domain" => nil,
      "source_kind" => "named_organization", "source_evidence" => nil
    }
  end

  def campaign_artifact(raw_chars:, cleaned_chars:, groups: [], letters: [])
    {
      "version" => 1, "text" => "C" * cleaned_chars,
      "counts" => {"raw_chars" => raw_chars, "cleaned_chars" => cleaned_chars},
      "letters" => letters, "campaign_drafts" => groups
    }
  end

  # A bill whose testimony coverage reports "nothing left out" — small
  # enough to stay under the size limit, so the coverage gate never fires and
  # every example using this helper is about campaign-approval mechanics,
  # not the gate itself. The dedicated "coverage acknowledgement guard"
  # examples below build their own larger artifact instead.
  def bill_with_one_campaign_group(id: "grp1", sender_count: 3, letter_count: 3)
    bill = create(:bill)
    provisioning = create(:bill_llm_provisioning, bill: bill,
      extracted_testimony: "R" * 900,
      cleaned_testimony: campaign_artifact(
        raw_chars: 900, cleaned_chars: 900,
        groups: [campaign_group(id: id, sender_count: sender_count, letter_count: letter_count)]
      ),
      cleaned_testimony_at: 1.hour.ago)
    [bill, provisioning]
  end

  describe "#call" do
    it "creates a campaign + an active position and returns :approved" do
      bill, = bill_with_one_campaign_group

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        name: "Complete Streets Letter", support: "support", summary: "Backs the bill",
        content_hash: "grp1"
      ).call

      expect(outcome).to eq(:approved)
      campaign = Campaign.find_by(name: "Complete Streets Letter", bill: bill)
      expect(campaign).not_to be_nil
      expect(campaign.support).to eq(Campaign.normalize_support("support"))
      expect(campaign.summary).to eq("Backs the bill")
      expect(campaign.active).to be(true)
      expect(campaign.sender_count).to eq(3)
      expect(campaign.letter_count).to eq(3)
    end

    it "creates no organization row of any kind, approved or otherwise" do
      bill, = bill_with_one_campaign_group

      described_class.new(
        bill: bill, actor: create(:user),
        name: "Complete Streets Letter", support: "support", summary: "Backs the bill",
        content_hash: "grp1"
      ).call

      expect(Organization.count).to eq(0)
      expect(OrganizationBillPosition.count).to eq(0)
    end

    it "matches an existing campaign on the bill, ignoring case, instead of creating a duplicate" do
      bill, = bill_with_one_campaign_group
      create(:campaign, name: "Complete Streets Letter", bill: bill)

      expect {
        described_class.new(
          bill: bill, actor: create(:user),
          name: "complete streets letter", support: "support", summary: "Backs it",
          content_hash: "grp1"
        ).call
      }.not_to change(Campaign, :count)
      expect(Organization.count).to eq(0)
    end

    # CR-04. A campaign name may be a whole sentence (Campaign::MAX_NAME_CHARS
    # is 500), and Jaro-Winkler's prefix bonus scores these two at 0.9405 —
    # over the 0.9 bar the service used. The second approval then found the
    # FIRST campaign, found its existing position on the same bill, and
    # rewrote FOR to AGAINST with no record that the first approval ever
    # happened.
    it "does not fold two campaigns arguing opposite sides into one because their names share an opening" do
      bill, = bill_with_one_campaign_group
      actor = create(:user)
      supporting = "Complete streets letter — support the bill as introduced"
      opposing = "Complete streets letter — oppose the bill as introduced"

      described_class.new(
        bill: bill, actor: actor, name: supporting, support: "support", summary: "Backs it",
        content_hash: "grp1"
      ).call
      described_class.new(
        bill: bill, actor: actor, name: opposing, support: "oppose", summary: "Against it",
        content_hash: "grp1"
      ).call

      expect(Campaign.where(bill: bill).pluck(:name)).to contain_exactly(supporting, opposing)
      first = Campaign.find_by(name: supporting, bill: bill)
      second = Campaign.find_by(name: opposing, bill: bill)
      expect(first&.support).to eq("FOR")
      expect(first&.summary).to eq("Backs it")
      expect(second&.support).to eq("AGAINST")
    end

    it "does not reuse a campaign on a DIFFERENT bill, even with an identical name" do
      bill = create(:bill, sway_locale: create(:sway_locale, :baltimore))
      create(:bill_llm_provisioning, bill: bill,
        extracted_testimony: "R" * 900,
        cleaned_testimony: campaign_artifact(
          raw_chars: 900, cleaned_chars: 900, groups: [campaign_group(id: "grp1")]
        ),
        cleaned_testimony_at: 1.hour.ago)
      other_bill = create(:bill, sway_locale: create(:sway_locale, :congress))
      create(:campaign, name: "Complete Streets Letter", bill: other_bill)

      expect {
        described_class.new(
          bill: bill, actor: create(:user),
          name: "Complete Streets Letter", support: "support", summary: "Backs it",
          content_hash: "grp1"
        ).call
      }.to change(Campaign, :count).by(1)
    end

    # @lat: [[campaign-approval#A campaign belongs to one bill]]
    it "creates two separate campaigns, each keeping its own stance, when the same name is approved on two different bills" do
      first_bill, = bill_with_one_campaign_group(id: "grp1")
      second_bill, = bill_with_one_campaign_group(id: "grp1")

      described_class.new(
        bill: first_bill, actor: create(:user),
        name: "Complete Streets Letter", support: "support", summary: "Backs it on bill one",
        content_hash: "grp1"
      ).call
      described_class.new(
        bill: second_bill, actor: create(:user),
        name: "Complete Streets Letter", support: "oppose", summary: "Against it on bill two",
        content_hash: "grp1"
      ).call

      expect(Campaign.where(name: "Complete Streets Letter").count).to eq(2)
      first = Campaign.find_by(name: "Complete Streets Letter", bill: first_bill)
      second = Campaign.find_by(name: "Complete Streets Letter", bill: second_bill)
      expect(first.support).to eq("FOR")
      expect(first.summary).to eq("Backs it on bill one")
      expect(second.support).to eq("AGAINST")
      expect(second.summary).to eq("Against it on bill two")
    end

    it "creates a new unnamed campaign with no name, and never matches an existing named one" do
      bill, = bill_with_one_campaign_group
      create(:campaign, name: "Complete Streets Letter", bill: bill)

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        name: "", support: "support", summary: "Backs it",
        content_hash: "grp1"
      ).call

      expect(outcome).to eq(:approved)
      campaign = Campaign.find_by(bill: bill, name: nil)
      expect(campaign).not_to be_nil
      expect(Organization.count).to eq(0)
    end

    it "two unnamed approvals on two different bills create two separate unnamed campaigns, never folded into one" do
      first_bill, = bill_with_one_campaign_group(id: "grp1")
      second_bill, = bill_with_one_campaign_group(id: "grp1")

      described_class.new(
        bill: first_bill, actor: create(:user), name: "", support: "support", summary: "One",
        content_hash: "grp1"
      ).call
      described_class.new(
        bill: second_bill, actor: create(:user), name: "", support: "support", summary: "Two",
        content_hash: "grp1"
      ).call

      expect(Campaign.where(name: nil).count).to eq(2)
    end

    it "writes one line to the decision log per outcome" do
      bill, = bill_with_one_campaign_group

      expect {
        described_class.new(
          bill: bill, actor: create(:user),
          name: "Complete Streets Letter", support: "support", summary: "Backs it",
          content_hash: "grp1"
        ).call
      }.to change(PipelineActivityLogEntry, :count).by(1)
      entry = PipelineActivityLogEntry.where(event_type: "org_position_decision").last
      expect(entry.payload["org_name"]).to eq("Complete Streets Letter")
    end

    it "returns :summary_required when the summary is blank after strip, before anything is written" do
      bill, = bill_with_one_campaign_group

      outcome = described_class.new(
        bill: bill, actor: create(:user), name: "A Campaign", support: "support", summary: "   ",
        content_hash: "grp1"
      ).call

      expect(outcome).to eq(:summary_required)
      expect(Campaign.count).to eq(0)
    end

    it "returns :invalid_stance for a value that is not one of the known ones" do
      bill, = bill_with_one_campaign_group

      outcome = described_class.new(
        bill: bill, actor: create(:user), name: "A Campaign", support: "sideways", summary: "Backs it",
        content_hash: "grp1"
      ).call

      expect(outcome).to eq(:invalid_stance)
      expect(Campaign.count).to eq(0)
    end

    it "returns :identity_required when no content_hash names a draft" do
      bill, = bill_with_one_campaign_group

      outcome = described_class.new(
        bill: bill, actor: create(:user), name: "A Campaign", support: "support", summary: "Backs it"
      ).call

      expect(outcome).to eq(:identity_required)
      expect(Campaign.count).to eq(0)
    end

    it "returns :draft_not_found when the content_hash names no draft in the artifact" do
      bill, = bill_with_one_campaign_group

      outcome = described_class.new(
        bill: bill, actor: create(:user), name: "A Campaign", support: "support", summary: "Backs it",
        content_hash: "a-different-hash"
      ).call

      expect(outcome).to eq(:draft_not_found)
      expect(Campaign.count).to eq(0)
    end

    # @lat: [[campaign-approval#A draft's identity is its content, not its position]]
    it "approves a draft that has moved to a new position, since position is not part of its identity" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill,
        extracted_testimony: "R" * 900,
        cleaned_testimony: campaign_artifact(raw_chars: 900, cleaned_chars: 900,
          groups: [campaign_group(id: "someone-else"), campaign_group(id: "grp1", sender_count: 7, letter_count: 9)]),
        cleaned_testimony_at: 1.hour.ago)

      outcome = described_class.new(
        bill: bill, actor: create(:user), name: "A Campaign", support: "support", summary: "Backs it",
        content_hash: "grp1"
      ).call

      expect(outcome).to eq(:approved)
      # Counts come from the draft the hash named, not from slot 0.
      expect(Campaign.sole).to have_attributes(sender_count: 7, letter_count: 9)
    end

    # CR-03. Every guard below the identity check opened with "skip this if
    # identity is blank", so a caller that named no draft passed all six and
    # reached the write. This endpoint has exactly one caller — the campaign
    # card, which always names a draft — so naming none is not a caller class
    # to exempt, it is a request with nothing to check against.
    it "refuses a caller that names no draft at all, rather than approving it unchecked" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill,
        extracted_testimony: "R" * 900,
        cleaned_testimony: campaign_artifact(raw_chars: 900, cleaned_chars: 900, groups: []),
        cleaned_testimony_at: 1.hour.ago)

      outcome = described_class.new(
        bill: bill, actor: create(:user), name: "A Campaign", support: "support", summary: "Backs it"
      ).call

      expect(outcome).to eq(:identity_required)
      expect(Campaign.count).to eq(0)
    end

    # The four refusals the omission used to walk past, each armed at once so
    # a fix that only reordered the identity checks would still fail here.
    it "refuses a caller that names no draft while a run is in flight and the coverage gate is unacknowledged" do
      bill, provisioning = bill_with_one_campaign_group
      provisioning.update!(
        generation_status: "pending",
        extracted_testimony: "R" * (BillPositionsPromptBuilder.max_testimony_chars + 500),
        cleaned_testimony: campaign_artifact(
          raw_chars: BillPositionsPromptBuilder.max_testimony_chars + 500,
          cleaned_chars: BillPositionsPromptBuilder.max_testimony_chars + 500,
          groups: [campaign_group(id: "grp1")]
        )
      )

      outcome = described_class.new(
        bill: bill, actor: create(:user), name: "A Campaign", support: "support", summary: "Backs it"
      ).call

      expect(outcome).not_to eq(:approved)
      expect(Campaign.count).to eq(0)
    end

    # The org sibling refuses on gone testimony. This service had no such guard, so Approve was live on that
    # bill AND succeeded, publishing a campaign position with no testimony
    # behind it.
    it "returns :no_testimony when the bill's testimony is gone" do
      bill, provisioning = bill_with_one_campaign_group
      provisioning.update!(extracted_testimony: nil, supplemental_testimony: nil)

      outcome = described_class.new(
        bill: bill, actor: create(:user), name: "A Campaign", support: "support", summary: "Backs it",
        content_hash: "grp1"
      ).call

      expect(outcome).to eq(:no_testimony)
      expect(Campaign.count).to eq(0)
    end

    it "returns :run_in_flight while a summary run is queued or running on the bill" do
      bill, provisioning = bill_with_one_campaign_group
      provisioning.update!(generation_status: "pending")

      outcome = described_class.new(
        bill: bill, actor: create(:user), name: "A Campaign", support: "support", summary: "Backs it",
        content_hash: "grp1"
      ).call

      expect(outcome).to eq(:run_in_flight)
      expect(Campaign.count).to eq(0)
    end

    # The summary job's own state says nothing about
    # Testimony::CleanAndGroupService, which never touches generation_status.
    # Before the fix, a clean-testimony run rewriting this bill's cleaned
    # artifact's campaign_drafts array left both these examples reaching :approved.
    it "returns :run_in_flight while a clean-testimony run is going for THIS bill, even though the summary is idle" do
      bill, = bill_with_one_campaign_group
      create(:legislation_pipeline_run, status: "cleaning_testimony", bill: bill)

      outcome = described_class.new(
        bill: bill, actor: create(:user), name: "A Campaign", support: "support", summary: "Backs it",
        content_hash: "grp1"
      ).call

      expect(outcome).to eq(:run_in_flight)
      expect(Campaign.count).to eq(0)
    end

    it "returns :run_in_flight during a global all-bills clean-testimony run, not only a single-bill one" do
      bill, = bill_with_one_campaign_group
      create(:legislation_pipeline_run, status: "cleaning_testimony", bill: nil)

      outcome = described_class.new(
        bill: bill, actor: create(:user), name: "A Campaign", support: "support", summary: "Backs it",
        content_hash: "grp1"
      ).call

      expect(outcome).to eq(:run_in_flight)
      expect(Campaign.count).to eq(0)
    end

    it "does not refuse on a clean-testimony run for a DIFFERENT bill" do
      bill, = bill_with_one_campaign_group
      create(:legislation_pipeline_run, status: "cleaning_testimony", bill: create(:bill))

      outcome = described_class.new(
        bill: bill, actor: create(:user), name: "A Campaign", support: "support", summary: "Backs it",
        content_hash: "grp1"
      ).call

      expect(outcome).to eq(:approved)
    end

    it "reaches the refusal on the second check, under the write lock, when a run is armed after the pre-check ran" do
      bill, provisioning = bill_with_one_campaign_group

      service = described_class.new(
        bill: bill, actor: create(:user), name: "A Campaign", support: "support", summary: "Backs it",
        content_hash: "grp1"
      )
      allow(service).to receive(:run_in_flight?).and_wrap_original do |original, provisioning_row = nil|
        result = original.call(provisioning_row)
        BillLlmProvisioning.find(provisioning.id).update!(generation_status: "pending")
        result
      end

      outcome = service.call

      expect(outcome).to eq(:run_in_flight)
      expect(Campaign.count).to eq(0)
    end

    describe "the coverage acknowledgement guard" do
      around do |example|
        with_app_config(:llm, llm_max_positions_chunks: 1) { example.run }
      end

      def tiling_campaign_letters(count = 32, characters = 5_000)
        (0...count).map { |position| campaign_letter(position, position * characters, characters) }
      end

      def bill_with_a_real_cut
        bill = create(:bill)
        provisioning = create(:bill_llm_provisioning, bill: bill,
          extracted_testimony: "R" * 165_000,
          cleaned_testimony: campaign_artifact(
            raw_chars: 165_000, cleaned_chars: 160_000,
            groups: [campaign_group(id: "grp1")],
            letters: tiling_campaign_letters
          ),
          cleaned_testimony_at: 1.hour.ago)
        [bill, provisioning]
      end

      it "refuses an approval whose testimony coverage was not acknowledged, and creates no campaign row" do
        bill, = bill_with_a_real_cut

        outcome = described_class.new(
          bill: bill, actor: create(:user), name: "A Campaign", support: "support", summary: "Backs it",
          content_hash: "grp1"
        ).call

        expect(outcome).to eq(:coverage_not_acknowledged)
        expect(Campaign.count).to eq(0)
        expect(Organization.count).to eq(0)
      end

      it "approves once the coverage has been acknowledged" do
        bill, = bill_with_a_real_cut
        digest = Testimony::CoverageReport.call(bill: bill).digest
        create(:testimony_coverage_acknowledgement, bill: bill, coverage_digest: digest)

        outcome = described_class.new(
          bill: bill, actor: create(:user), name: "A Campaign", support: "support", summary: "Backs it",
          content_hash: "grp1"
        ).call

        expect(outcome).to eq(:approved)
      end

      it "reaches the refusal on the second check when the acknowledgement stops matching after the pre-check ran" do
        bill, provisioning = bill_with_a_real_cut
        digest = Testimony::CoverageReport.call(bill: bill).digest
        create(:testimony_coverage_acknowledgement, bill: bill, coverage_digest: digest)

        service = described_class.new(
          bill: bill, actor: create(:user), name: "A Campaign", support: "support", summary: "Backs it",
          content_hash: "grp1"
        )
        allow(service).to receive(:coverage_not_acknowledged?).and_wrap_original do |original, provisioning_row = nil|
          result = original.call(provisioning_row)
          BillLlmProvisioning.find(provisioning.id).update!(
            extracted_testimony: "R" * 175_000,
            cleaned_testimony: campaign_artifact(
              raw_chars: 175_000, cleaned_chars: 170_000,
              groups: [campaign_group(id: "grp1")],
              letters: tiling_campaign_letters(34)
            ),
            cleaned_testimony_at: Time.current
          )
          result
        end

        outcome = service.call

        expect(outcome).to eq(:coverage_not_acknowledged)
        expect(Campaign.count).to eq(0)
      end
    end

    # @lat: [[campaign-approval#Approving over a name already taken is reported, not refused]]
    describe "recording which draft a campaign was approved from" do
      def bill_with_two_campaign_drafts
        bill = create(:bill)
        create(:bill_llm_provisioning, bill: bill,
          extracted_testimony: "R" * 900,
          cleaned_testimony: campaign_artifact(raw_chars: 900, cleaned_chars: 900,
            groups: [campaign_group(id: "grp1", sender_count: 3, letter_count: 3),
              campaign_group(id: "grp2", sender_count: 8, letter_count: 8)]),
          cleaned_testimony_at: 1.hour.ago)
        bill
      end

      def approve_campaign(bill, actor, hash, name: "Complete Streets Letter", support: "support", summary: "Backs it")
        described_class.new(
          bill: bill, actor: actor, name: name, support: support, summary: summary, content_hash: hash
        ).call
      end

      it "stores the approved draft's content hash on the campaign" do
        bill = bill_with_two_campaign_drafts

        expect(approve_campaign(bill, create(:user), "grp2")).to eq(:approved)
        expect(Campaign.sole.source_campaign_draft_hash).to eq("grp2")
      end

      it "reports a plain :approved when the SAME draft is approved again, since nobody else's decision is lost" do
        bill = bill_with_two_campaign_drafts
        actor = create(:user)
        approve_campaign(bill, actor, "grp1")

        expect(approve_campaign(bill, actor, "grp1", summary: "Backs it, reworded")).to eq(:approved)
        expect(Campaign.sole.summary).to eq("Backs it, reworded")
      end

      # @lat: [[campaign-approval#Approving over a name already taken is reported, not refused]]
      it "reports :approved_replacing_draft when a DIFFERENT draft is approved under a name already taken" do
        bill = bill_with_two_campaign_drafts
        actor = create(:user)
        expect(approve_campaign(bill, actor, "grp1", support: "support")).to eq(:approved)

        outcome = approve_campaign(bill, actor, "grp2", support: "oppose", summary: "Opposes it")

        expect(outcome).to eq(:approved_replacing_draft)
        # Still one row: the [bill_id, name] unique index allows no second one.
        expect(Campaign.count).to eq(1)
        expect(Campaign.sole).to have_attributes(
          support: "AGAINST", summary: "Opposes it",
          sender_count: 8, letter_count: 8, source_campaign_draft_hash: "grp2"
        )
      end

      it "names the replaced draft in the decision log, so the log says which approval stands" do
        bill = bill_with_two_campaign_drafts
        actor = create(:user)
        approve_campaign(bill, actor, "grp1")
        approve_campaign(bill, actor, "grp2")

        entries = PipelineActivityLogEntry.where(event_type: "org_position_decision").order(:id)

        expect(entries.map { |entry| entry.payload["decision"] })
          .to eq(["approved", "approved_replacing_draft"])
        # The replaced draft goes in its own key. Encoding it into `decision`
        # would give an otherwise enum-shaped field unbounded cardinality, and
        # anything reading that field by equality would stop matching.
        expect(entries.map { |entry| entry.payload["replaced_draft_hash"] }).to eq([nil, "grp1"])
      end

      it "identifies the draft in the log by its hash, not by a position that a re-run can change" do
        bill = bill_with_two_campaign_drafts
        approve_campaign(bill, create(:user), "grp2")

        entry = PipelineActivityLogEntry.where(event_type: "org_position_decision").sole

        expect(entry.payload["draft_id"]).to eq("#{bill.id}-campaign-grp2")
      end

      # An unnamed campaign is never matched (every approval of one is its own
      # record), so a second one cannot be replacing anything.
      it "reports :approved for a second unnamed campaign rather than treating it as a replacement" do
        bill = bill_with_two_campaign_drafts
        actor = create(:user)
        approve_campaign(bill, actor, "grp1", name: "")

        expect(approve_campaign(bill, actor, "grp2", name: "")).to eq(:approved)
        expect(Campaign.count).to eq(2)
      end
    end
  end
end
