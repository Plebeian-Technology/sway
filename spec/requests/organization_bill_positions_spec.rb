# frozen_string_literal: true

require "rails_helper"
require "yaml"

# Proof that OrganizationBillPositionsController#create is admin-only. What the
# action actually does is covered in admin_organization_bill_positions_spec.rb.
RSpec.describe "OrganizationBillPositionsController admin gate", type: :request do
  empty_array = [] #: Array[untyped]
  include_examples "requires sway admin",
    verb: :post,
    path: "/organization_bill_positions",
    params: {organization_bill_position: {positions: empty_array}}

  # index and show used to be open to any signed-in user, and they dumped rows
  # through the default as_json — inactive, unapproved drafts included —
  # against the model's rule that only listed fields go out. Nothing outside
  # the admin area reads them, so those two are admin-only now as well.
  include_examples "requires sway admin",
    verb: :get,
    path: "/organization_bill_positions"

  include_examples "requires sway admin",
    verb: :get,
    path: "/organization_bill_positions/1"

  include_examples "requires sway admin",
    verb: :delete,
    path: "/organization_bill_positions/1"
end

# @lat: [[replace-bill-org-positions-service-design#Why the write upserts by (bill, organization) instead of deleting and re-inserting]]
RSpec.describe "OrganizationBillPositionsController#create recompute trigger", type: :request do
  let(:admin) { create(:user, :sway_admin) }
  let(:sway_locale) { create(:sway_locale) }
  let(:organization) { create(:organization, sway_locale: sway_locale) }
  # let! creates the bill right away. Bill#after_commit ALSO enqueues a
  # recompute when a bill is created, so a lazy `let` would build the bill
  # inside the expect block below and double the number of jobs counted.
  let!(:bill) { create(:bill, sway_locale: sway_locale) }

  before { sign_in admin }

  it "enqueues RecomputeBillInterestingScoreJob for the bill after the upsert bulk write" do
    expect {
      post organization_bill_positions_path,
        params: {
          organization_bill_position: {
            positions: [
              {
                bill_id: bill.id,
                organization_id: organization.id,
                support: "support",
                summary: "We support this bill."
              }
            ]
          }
        }
      # @lat: [[replace-bill-org-positions-service-design#Why the write upserts by (bill, organization) instead of deleting and re-inserting]]
    }.to have_enqueued_job(RecomputeBillInterestingScoreJob).with(bill.id).exactly(2).times
  end

  it "does not enqueue when the positions payload is empty (no-op branch)" do
    expect {
      post organization_bill_positions_path,
        params: {organization_bill_position: {positions: nil}}
    }.not_to have_enqueued_job(RecomputeBillInterestingScoreJob)
  end
end

# @lat: [[replace-bill-org-positions-service-design#Why the write upserts by (bill, organization) instead of deleting and re-inserting]]
RSpec.describe "OrganizationBillPositionsController#create authoritative active set", type: :request do
  include ActiveJob::TestHelper

  let(:admin) { create(:user, :sway_admin) }
  let(:sway_locale) { create(:sway_locale) }
  let(:organization) { create(:organization, sway_locale: sway_locale) }
  # The organization factory has a fixed name ("Taco Org") with a uniqueness
  # validation — the other orgs need their own names.
  let(:other_organization) { create(:organization, name: "Burrito Org", sway_locale: sway_locale) }
  let(:omitted_organization) { create(:organization, name: "Quesadilla Org", sway_locale: sway_locale) }
  let(:bill) { create(:bill, sway_locale: sway_locale) }

  before { sign_in admin }

  it "upserts present orgs in place (stable id, active: true), soft-deletes absent orgs, and the recompute observes the final set" do
    # Simulates ApproveOrgPositionService's explicit activation.
    existing = OrganizationBillPosition.create!(
      bill: bill,
      organization: organization,
      support: "FOR",
      summary: "Approved earlier.",
      active: true
    )
    omitted = OrganizationBillPosition.create!(
      bill: bill,
      organization: omitted_organization,
      support: "FOR",
      summary: "Previously approved; omitted from the re-save.",
      active: true
    )

    perform_enqueued_jobs do
      post organization_bill_positions_path,
        params: {
          organization_bill_position: {
            positions: [
              {
                bill_id: bill.id,
                organization_id: organization.id,
                support: "oppose",
                summary: "Re-saved with a new stance."
              },
              {
                bill_id: bill.id,
                organization_id: other_organization.id,
                support: "support",
                summary: "Brand new draft position."
              }
            ]
          }
        }
    end

    carried = OrganizationBillPosition.find_by(bill_id: bill.id, organization_id: organization.id)
    fresh = OrganizationBillPosition.find_by(bill_id: bill.id, organization_id: other_organization.id)

    # The row keeps its id through the re-save. The old destroy_all followed by
    # insert_all! made a brand new id every time, cutting the history and the
    # delivery markers loose.
    expect(carried&.id).to eq(existing.id)
    expect(carried&.active).to be(true)
    expect(carried&.support).to eq("AGAINST") # normalized from "oppose"
    # Genuinely new rows are active immediately.
    expect(fresh&.active).to be(true)
    # An org missing from the payload is marked inactive; its row stays put.
    expect(omitted.reload.active).to be(false)

    # perform_enqueued_jobs ran the recompute AFTER the bulk write, so it saw
    # the final list: AGAINST from the carried-over row and FOR from the new
    # one. The omitted organization's row is inactive and left out.
    score = BillInterestingScore.where(bill_id: bill.id).order(id: :desc).first
    expect(score).to be_present
    expect(score&.signals&.fetch("org_against")).to eq(1)
    expect(score&.signals&.fetch("org_for")).to eq(1)
  end

  it "records every saved position as a Sway admin entry with no URL, replacing an organization's own origin" do
    OrganizationBillPosition.create!(
      bill: bill, organization: organization, support: "FOR", summary: "Written by the organization.",
      active: true, source_kind: "organization"
    )

    post organization_bill_positions_path,
      params: {
        organization_bill_position: {
          positions: [
            {bill_id: bill.id, organization_id: organization.id, support: "oppose", summary: "Replaced by an admin."},
            {bill_id: bill.id, organization_id: other_organization.id, support: "support", summary: "Entered by an admin."}
          ]
        }
      }

    positions = OrganizationBillPosition.where(bill_id: bill.id)
    expect(positions.pluck(:source_kind)).to all(eq("sway_admin"))
    expect(positions.pluck(:source_url)).to all(be_nil)
  end

  it "keeps the origin of positions a re-save leaves unchanged and marks a changed one as a Sway admin entry" do
    news_position = OrganizationBillPosition.create!(
      bill: bill, organization: organization, support: "FOR", summary: "Reported in the news.",
      active: true, source_kind: "news_article", source_url: "https://news.example.com/story"
    )
    member_position = OrganizationBillPosition.create!(
      bill: bill, organization: other_organization, support: "AGAINST", summary: "Written by the members.",
      active: true, source_kind: "organization"
    )
    edited_organization = create(:organization, name: "Tamale Org", sway_locale: sway_locale)
    edited_position = OrganizationBillPosition.create!(
      bill: bill, organization: edited_organization, support: "FOR", summary: "Before the edit.",
      active: true, source_kind: "news_article", source_url: "https://news.example.com/other"
    )

    post organization_bill_positions_path,
      params: {
        organization_bill_position: {
          positions: [
            {bill_id: bill.id, organization_id: organization.id, support: "support", summary: "Reported in the news."},
            {bill_id: bill.id, organization_id: other_organization.id, support: "oppose", summary: "Written by the members."},
            {bill_id: bill.id, organization_id: edited_organization.id, support: "support", summary: "After the edit."}
          ]
        }
      }

    expect(news_position.reload.slice(:source_kind, :source_url))
      .to eq("source_kind" => "news_article", "source_url" => "https://news.example.com/story")
    expect(member_position.reload.source_kind).to eq("organization")
    expect(edited_position.reload.slice(:source_kind, :source_url))
      .to eq("source_kind" => "sway_admin", "source_url" => nil)
  end
end

# @lat: [[replace-bill-org-positions-service-design#Why the write upserts by (bill, organization) instead of deleting and re-inserting]]
RSpec.describe "OrganizationBillPositionsController#create malformed-payload safety", type: :request do
  let(:admin) { create(:user, :sway_admin) }
  let(:sway_locale) { create(:sway_locale) }
  let(:organization) { create(:organization, sway_locale: sway_locale) }
  let(:bill) { create(:bill, sway_locale: sway_locale) }

  let!(:preexisting_active_position) do
    # Stands in for what ApproveOrgPositionService activates — exactly the rows
    # this protection exists to keep safe.
    OrganizationBillPosition.create!(
      bill: bill,
      organization: organization,
      support: "FOR",
      summary: "Approved earlier.",
      active: true
    )
  end

  before { sign_in admin }

  it "rejects a nonexistent organization_id with 404 and leaves the pre-existing active position untouched" do
    post organization_bill_positions_path,
      params: {
        organization_bill_position: {
          positions: [
            {
              bill_id: bill.id,
              organization_id: 999_999_999,
              support: "support",
              summary: "Bogus org."
            }
          ]
        }
      }

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body["error"]["code"]).to eq("organization_not_found")

    survivor = OrganizationBillPosition.find_by(bill_id: bill.id, organization_id: organization.id)
    expect(survivor).to be_present
    expect(survivor&.active).to be(true)
    expect(survivor&.support).to eq("FOR")
  end

  it "rejects a duplicated organization_id with 422 and leaves the pre-existing active position untouched" do
    post organization_bill_positions_path,
      params: {
        organization_bill_position: {
          positions: [
            {
              bill_id: bill.id,
              organization_id: organization.id,
              support: "support",
              summary: "First copy."
            },
            {
              bill_id: bill.id,
              organization_id: organization.id,
              support: "oppose",
              summary: "Second copy of the same org."
            }
          ]
        }
      }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]["code"]).to eq("duplicate_organization_id")

    survivor = OrganizationBillPosition.find_by(bill_id: bill.id, organization_id: organization.id)
    expect(survivor).to be_present
    expect(survivor&.active).to be(true)
    expect(survivor&.support).to eq("FOR")
  end

  it "does not enqueue a recompute when the payload is rejected up front" do
    expect {
      post organization_bill_positions_path,
        params: {
          organization_bill_position: {
            positions: [
              {
                bill_id: bill.id,
                organization_id: 999_999_999,
                support: "support",
                summary: "Bogus org."
              }
            ]
          }
        }
    }.not_to have_enqueued_job(RecomputeBillInterestingScoreJob)
  end
end

# @lat: [[replace-bill-org-positions-service-design#Why every position is validated as a batch BEFORE any position is validated individually, and both before any write]]
RSpec.describe "OrganizationBillPositionsController#create per-position completeness", type: :request do
  let(:admin) { create(:user, :sway_admin) }
  let(:sway_locale) { create(:sway_locale) }
  let(:organization) { create(:organization, sway_locale: sway_locale) }
  let(:other_organization) { create(:organization, name: "Burrito Org", sway_locale: sway_locale) }
  let(:bill) { create(:bill, sway_locale: sway_locale) }

  let!(:preexisting_active_position) do
    OrganizationBillPosition.create!(
      bill: bill,
      organization: organization,
      support: "FOR",
      summary: "Approved earlier.",
      active: true
    )
  end

  before { sign_in admin }

  # What all three payloads must produce: a 422 with code incomplete_position,
  # nothing written (the existing active row survives untouched), no recompute.
  def expect_incomplete_position_rejection
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]["code"]).to eq("incomplete_position")

    survivor = OrganizationBillPosition.find_by(bill_id: bill.id, organization_id: organization.id)
    expect(survivor).to be_present
    expect(survivor&.active).to be(true)
    expect(survivor&.summary).to eq("Approved earlier.")
  end

  it "rejects a payload where one position is missing bill_id (shape 1: .compact hid the nil from the aggregate guards)" do
    expect {
      post organization_bill_positions_path,
        params: {
          organization_bill_position: {
            positions: [
              {
                bill_id: bill.id,
                organization_id: organization.id,
                support: "support",
                summary: "Complete row."
              },
              {
                # bill_id intentionally absent
                organization_id: other_organization.id,
                support: "oppose",
                summary: "Row without a bill_id."
              }
            ]
          }
        }
    }.not_to have_enqueued_job(RecomputeBillInterestingScoreJob)

    expect_incomplete_position_rejection
  end

  it "rejects a payload where one position is missing the summary key entirely (shape 2: non-uniform insert_all! hashes)" do
    expect {
      post organization_bill_positions_path,
        params: {
          organization_bill_position: {
            positions: [
              {
                bill_id: bill.id,
                organization_id: organization.id,
                support: "support",
                summary: "Complete row."
              },
              {
                bill_id: bill.id,
                organization_id: other_organization.id,
                support: "oppose"
                # summary key intentionally absent
              }
            ]
          }
        }
    }.not_to have_enqueued_job(RecomputeBillInterestingScoreJob)

    expect_incomplete_position_rejection
  end

  it "rejects a blank summary (shape 3: insert_all! bypasses the model presence validation)" do
    expect {
      post organization_bill_positions_path,
        params: {
          organization_bill_position: {
            positions: [
              {
                bill_id: bill.id,
                organization_id: other_organization.id,
                support: "support",
                summary: "   "
              }
            ]
          }
        }
    }.not_to have_enqueued_job(RecomputeBillInterestingScoreJob)

    expect_incomplete_position_rejection
    # No empty-summary row may persist for the org in the payload either.
    expect(
      OrganizationBillPosition.find_by(bill_id: bill.id, organization_id: other_organization.id)
    ).to be_nil
  end
end

RSpec.describe "OrganizationBillPositionsController#create — a Neutral position keeps no testimony", type: :request do
  let(:admin) { create(:user, :sway_admin) }
  let(:sway_locale) { create(:sway_locale) }
  let(:organization) { create(:organization, sway_locale: sway_locale) }
  let(:bill) { create(:bill, sway_locale: sway_locale) }

  before { sign_in admin }

  def post_position(support:, summary:)
    post organization_bill_positions_path,
      params: {
        organization_bill_position: {
          positions: [
            {
              bill_id: bill.id,
              organization_id: organization.id,
              support: support,
              summary: summary
            }
          ]
        }
      }
  end

  it "discards the submitted testimony of a neutral position" do
    post_position(support: "neutral", summary: "A long argument nobody asked for.")

    expect(response).to have_http_status(:ok)
    stored = OrganizationBillPosition.find_by!(bill_id: bill.id, organization_id: organization.id)
    expect(stored.support).to eq("ABSTAIN")
    expect(stored.summary).to eq(OrganizationBillPosition::DEFAULT_SUMMARY)
  end

  it "accepts a neutral position that carries no testimony at all" do
    post_position(support: "ABSTAIN", summary: "   ")

    expect(response).to have_http_status(:ok)
    stored = OrganizationBillPosition.find_by!(bill_id: bill.id, organization_id: organization.id)
    expect(stored.support).to eq("ABSTAIN")
    expect(stored.summary).to eq(OrganizationBillPosition::DEFAULT_SUMMARY)
  end

  it "still keeps the testimony of a position that takes a side" do
    post_position(support: "support", summary: "The case for this bill.")

    expect(response).to have_http_status(:ok)
    stored = OrganizationBillPosition.find_by!(bill_id: bill.id, organization_id: organization.id)
    expect(stored.summary).to eq("The case for this bill.")
  end
end

# @lat: [[bill-interesting-score#Why a bill gains a row every day]]
RSpec.describe "No recurring recompute job exists" do
  it "config/recurring.yml schedules no interesting-score recompute; the retention job is the only interesting-score entry" do
    config = YAML.load_file(Rails.root.join("config", "recurring.yml"))
    scheduled_classes = config.values.flat_map do |entries|
      (entries || {}).values.filter_map { |entry| entry["class"] }
    end

    expect(scheduled_classes.grep(/BillInteresting/).uniq).to eq(["BillInterestingScoreRetentionJob"])
  end
end
