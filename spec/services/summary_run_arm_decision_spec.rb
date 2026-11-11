# frozen_string_literal: true

require "rails_helper"

# One example per row of the decision table, so a new branch can't be added
# without its neighbours on screen. This file pins the decision itself,
# which four reviews found a hole in.
RSpec.describe SummaryRunArmDecision do
  let(:this_job_id) { "this-executions-job-id" }
  let(:live_clock) { 1.minute.ago }
  let(:abandoned_clock) { (GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER + 1.minute).ago }

  def arm_decision(status_at_load:, status:, marker: nil, updated_at: nil)
    described_class.new(
      status_at_load: status_at_load,
      status: status,
      marker: marker,
      updated_at: updated_at || live_clock,
      job_id: this_job_id
    )
  end

  # Row 1. Nothing in the job writes the row between #perform's load and the
  # arm's lock, so a difference is another writer's work and the transition
  # would be validated against a row that is gone.
  describe "the row moved under this run" do
    subject(:decision) { arm_decision(status_at_load: "pending", status: "completed") }

    it "names the case" do
      expect(decision.name).to eq(:row_moved)
    end

    it "declines, and writes nothing" do
      expect(decision.proceed?).to be(false)
      expect(decision.claim_row?).to be(false)
      expect(decision.refresh_clock?).to be(false)
      expect(decision.log_reclaim?).to be(false)
    end
  end

  # Row 2. Tested BEFORE the status and before the clock, so a paste-marked row
  # can never be reported as a reclaim.
  describe "an operator's paste owns the body" do
    subject(:decision) do
      arm_decision(
        status_at_load: "generating",
        status: "generating",
        marker: SummaryRunMarker.operator_paste,
        updated_at: abandoned_clock
      )
    end

    it "names the case" do
      expect(decision.name).to eq(:paste_hand_off)
    end

    it "proceeds so the pre-call clear can settle the row onto the pasted body" do
      expect(decision.proceed?).to be(true)
    end

    it "leaves the paste marker alone" do
      expect(decision.claim_row?).to be(false)
    end

    it "restarts the clock even though it claims nothing" do
      expect(decision.refresh_clock?).to be(true)
    end

    it "does not report a reclaim it is not making, however old the row is" do
      expect(decision.log_reclaim?).to be(false)
    end
  end

  # Row 3, the counter-example to row 2: settle_pasted_row! defers ONLY for
  # pending/generating; other statuses settle themselves. The marker alone
  # can't tell deferred from finished.
  describe "an operator's paste that already settled the row itself" do
    subject(:decision) do
      arm_decision(
        status_at_load: "completed",
        status: "completed",
        marker: SummaryRunMarker.operator_paste
      )
    end

    it "names the case" do
      expect(decision.name).to eq(:paste_already_settled)
    end

    it "leaves a finished row alone rather than walking it back through generating" do
      expect(decision.proceed?).to be(false)
      expect(decision.claim_row?).to be(false)
      expect(decision.refresh_clock?).to be(false)
      expect(decision.log_reclaim?).to be(false)
    end

    it "reads the same way on the other terminal statuses a paste settles from" do
      %w[failed skipped].each do |status|
        settled = arm_decision(
          status_at_load: status, status: status, marker: SummaryRunMarker.operator_paste
        )

        expect(settled.name).to eq(:paste_already_settled)
        expect(settled.proceed?).to be(false)
      end
    end

    # The hand-off half, so the split cannot be made by declining on every
    # paste — which would re-open B21-02 and strand the row `generating` under a
    # marker the service-side reclaim then destroys.
    it "still hands off a pending row, which PasteSummaryService also defers" do
      deferred = arm_decision(
        status_at_load: "pending", status: "pending", marker: SummaryRunMarker.operator_paste
      )

      expect(deferred.name).to eq(:paste_hand_off)
      expect(deferred.proceed?).to be(true)
    end
  end

  # Row 4. A restarted worker comes back carrying the same job_id, so its own
  # claim is what lets it back into its own run.
  describe "the row carries this execution's own claim" do
    subject(:decision) do
      arm_decision(
        status_at_load: "generating",
        status: "generating",
        marker: SummaryRunMarker.run_claim(this_job_id),
        updated_at: abandoned_clock
      )
    end

    it "names the case" do
      expect(decision.name).to eq(:own_claim)
    end

    it "proceeds, re-stamps the claim and restarts the clock" do
      expect(decision.proceed?).to be(true)
      expect(decision.claim_row?).to be(true)
      expect(decision.refresh_clock?).to be(true)
    end

    it "does not report a reclaim of its own row" do
      expect(decision.log_reclaim?).to be(false)
    end
  end

  # Row 5. The case B22-01 was filed about: an execution finishing the half it
  # still owes, over a row whose last write was its own pre-crash persist.
  describe "the row carries this enqueue's purchase receipt and is generating" do
    subject(:decision) do
      arm_decision(
        status_at_load: "generating",
        status: "generating",
        marker: this_job_id,
        updated_at: abandoned_clock
      )
    end

    it "names the case" do
      expect(decision.name).to eq(:resume_after_purchase)
    end

    it "proceeds" do
      expect(decision.proceed?).to be(true)
    end

    it "keeps the receipt, or the re-entry gate would let the body be bought twice" do
      expect(decision.claim_row?).to be(false)
    end

    it "restarts the clock, so nothing reclaims it through its positions call" do
      expect(decision.refresh_clock?).to be(true)
    end
  end

  # Row 6. The recovery B21-01 added: `generating` for somebody, and nothing has
  # written the row for longer than the job's worst-case wall clock.
  describe "the row is generating for a run that is gone" do
    subject(:decision) do
      arm_decision(
        status_at_load: "generating",
        status: "generating",
        marker: SummaryRunMarker.run_claim("a-job-id-no-execution-carries-any-more"),
        updated_at: abandoned_clock
      )
    end

    it "names the case" do
      expect(decision.name).to eq(:reclaim_abandoned)
    end

    it "takes the row over and restarts its clock in the same breath" do
      expect(decision.proceed?).to be(true)
      expect(decision.claim_row?).to be(true)
      expect(decision.refresh_clock?).to be(true)
    end

    it "records that a worker died" do
      expect(decision.log_reclaim?).to be(true)
    end
  end

  # Row 7. The counter-example to row 6, so the reclaim cannot widen into "any
  # foreign claim may be taken".
  describe "the row is generating for a run that is still alive" do
    subject(:decision) do
      arm_decision(
        status_at_load: "generating",
        status: "generating",
        marker: SummaryRunMarker.run_claim("an-execution-that-is-still-alive"),
        updated_at: live_clock
      )
    end

    it "names the case" do
      expect(decision.name).to eq(:owned_by_another_run)
    end

    it "declines, and writes nothing" do
      expect(decision.proceed?).to be(false)
      expect(decision.claim_row?).to be(false)
      expect(decision.refresh_clock?).to be(false)
    end
  end

  # The same row, reached the other way: `generating` with nothing at all saying
  # who owns it. Nothing says this execution owns it either.
  describe "the row is generating with no marker on it" do
    it "declines" do
      decision = arm_decision(
        status_at_load: "generating", status: "generating", marker: nil, updated_at: live_clock
      )

      expect(decision.name).to eq(:owned_by_another_run)
      expect(decision.proceed?).to be(false)
    end
  end

  # "Unknown" must not read as "free" on the decision that opens two paid calls.
  describe "the row is generating and carries no timestamp at all" do
    it "declines rather than treating a missing clock as an abandoned run" do
      decision = described_class.new(
        status_at_load: "generating", status: "generating",
        marker: nil, updated_at: nil, job_id: this_job_id
      )

      expect(decision.name).to eq(:owned_by_another_run)
      expect(decision.proceed?).to be(false)
    end
  end

  # Row 8: a retry over a row an earlier execution already settled. It has
  # to arm — settle_completed settles from generating — and keep the
  # receipt, or it re-buys what it already owns.
  describe "a settled row carrying this enqueue's purchase receipt" do
    subject(:decision) do
      arm_decision(status_at_load: "completed", status: "completed", marker: this_job_id)
    end

    it "names the case" do
      expect(decision.name).to eq(:arm_after_purchase)
    end

    it "arms without claiming, and restarts the clock" do
      expect(decision.proceed?).to be(true)
      expect(decision.claim_row?).to be(false)
      expect(decision.refresh_clock?).to be(true)
    end
  end

  # Row 9: the ordinary generate/regenerate/pipeline path. An older run's
  # marker on a settled row is not an owner — this is a regenerate and it
  # must pay.
  describe "a row nobody owns" do
    it "arms a row that has never been generated" do
      decision = arm_decision(status_at_load: nil, status: nil)

      expect(decision.name).to eq(:arm_free_row)
      expect(decision.proceed?).to be(true)
      expect(decision.claim_row?).to be(true)
      expect(decision.refresh_clock?).to be(true)
    end

    it "arms a settled row carrying an older run's marker" do
      decision = arm_decision(
        status_at_load: "completed", status: "completed", marker: "an-older-runs-job-id"
      )

      expect(decision.name).to eq(:arm_free_row)
      expect(decision.claim_row?).to be(true)
    end

    it "arms a pending row the service just queued" do
      decision = arm_decision(status_at_load: "pending", status: "pending")

      expect(decision.name).to eq(:arm_free_row)
      expect(decision.claim_row?).to be(true)
    end
  end

  # The table read as a whole, so a tenth case cannot be added without an
  # example here and a row in the enumeration the arm's comment points at.
  describe "the table itself" do
    it "enumerates exactly the nine cases the examples above cover" do
      expect(described_class::CASES).to match_array(
        %i[
          row_moved paste_hand_off paste_already_settled own_claim resume_after_purchase
          reclaim_abandoned owned_by_another_run arm_after_purchase arm_free_row
        ]
      )
    end

    it "never claims a row on a case that declines" do
      expect(described_class::DECLINED & described_class::CLAIMING).to be_empty
      expect(described_class::DECLINED - described_class::CASES).to be_empty
      expect(described_class::CLAIMING - described_class::CASES).to be_empty
    end

    # RENAMED to what it does: the old title claimed a clock-restart check,
    # but the body never called #refresh_clock?, comparing three constants
    # instead (B23-08).
    it "no case may change tier without this example failing" do
      proceeding = described_class::CASES - described_class::DECLINED

      expect(proceeding).to match_array(
        %i[
          paste_hand_off own_claim resume_after_purchase
          reclaim_abandoned arm_after_purchase arm_free_row
        ]
      )
      expect(proceeding - described_class::CLAIMING)
        .to match_array(%i[paste_hand_off resume_after_purchase arm_after_purchase])
    end

    # The invariant B22-01 cost, asserted by CALLING both methods on a real
    # decision per case: an execution that proceeds IS the live owner, and
    # updated_at is the only thing that says so.
    it "answers refresh_clock? exactly where it answers proceed?" do
      decisions = [
        arm_decision(status_at_load: "pending", status: "completed"),
        arm_decision(status_at_load: "generating", status: "generating",
          marker: SummaryRunMarker.operator_paste),
        arm_decision(status_at_load: "completed", status: "completed",
          marker: SummaryRunMarker.operator_paste),
        arm_decision(status_at_load: "generating", status: "generating",
          marker: SummaryRunMarker.run_claim(this_job_id)),
        arm_decision(status_at_load: "generating", status: "generating", marker: this_job_id),
        arm_decision(status_at_load: "generating", status: "generating",
          marker: SummaryRunMarker.run_claim("gone"), updated_at: abandoned_clock),
        arm_decision(status_at_load: "generating", status: "generating",
          marker: SummaryRunMarker.run_claim("alive")),
        arm_decision(status_at_load: "completed", status: "completed", marker: this_job_id),
        arm_decision(status_at_load: nil, status: nil)
      ]

      expect(decisions.map(&:name)).to match_array(described_class::CASES)
      decisions.each do |decision|
        expect(decision.refresh_clock?).to be(decision.proceed?),
          "#{decision.name} answered refresh_clock? #{decision.refresh_clock?} and " \
          "proceed? #{decision.proceed?}"
      end
    end
  end

  describe ".for" do
    let(:bill) { create(:bill) }
    let(:provisioning) do
      create(:bill_llm_provisioning, :generating, bill: bill, summary_run_id: this_job_id)
    end

    it "reads all four inputs off the row the caller reloaded" do
      decision = described_class.for(
        provisioning: provisioning, status_at_load: "generating", job_id: this_job_id
      )

      expect(decision.name).to eq(:resume_after_purchase)
    end
  end
end
