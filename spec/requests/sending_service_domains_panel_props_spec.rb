# frozen_string_literal: true

require "rails_helper"

# B2, the half the off-ramp does not reach. Deleting orphans bounds what
# OUTLIVES a run; it does nothing about how many rows one submitted document
# can create while it is current. Testimony::LetterSplitter cuts a new letter
# at every line-initial "From:", so a single PDF can name any number of
# domains, and every one of them was shipped — unpaginated — on every Bill
# Creator render and every five-second poll of two admin tabs, each row
# costing three SUM queries.
RSpec.describe "Bill Creator sending-service domain props", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let!(:sway_locale_and_user) { setup }
  let(:sway_locale) { sway_locale_and_user.first }
  let(:admin) { create(:user, :sway_admin) }

  let(:bill) do
    legislator = sway_locale.legislators.first
    create(:bill, sway_locale: sway_locale, legislator: legislator)
  end

  before { session_hash[:user_id] = admin.id }

  def contributing_domain(name)
    domain = SendingServiceDomain.create!(domain: name)
    SendingServiceDomainBill.create!(
      sending_service_domain: domain, bill: bill,
      sender_count: 1, letter_count: 1, machine_sent_letter_count: 0
    )
    domain
  end

  def contributing_domain_with_counts(name, sender_count:, letter_count:, machine_sent_letter_count:, for_bill: bill)
    domain = SendingServiceDomain.create!(domain: name)
    SendingServiceDomainBill.create!(
      sending_service_domain: domain, bill: for_bill,
      sender_count: sender_count, letter_count: letter_count,
      machine_sent_letter_count: machine_sent_letter_count
    )
    domain
  end

  it "caps the list one document can fill and reports the true total" do
    over_the_cap = SendingServiceDomain::MAX_PANEL_ROWS + 25
    over_the_cap.times { |i| contributing_domain("d#{i.to_s.rjust(4, "0")}.example.com") }

    get pipeline_bill_creator_path(bill)

    expect(inertia).to render_component(Pages::BILL_CREATOR)
    expect(inertia.props[:sending_service_domains].length).to eq(SendingServiceDomain::MAX_PANEL_ROWS)
    # The count is the whole point of capping honestly: a panel that silently
    # shows the first N reads as "these are all of them".
    expect(inertia.props[:sending_service_domains_total]).to eq(over_the_cap)
  end

  # Rows created before the off-ramp existed are still in the table, so the
  # panel filters as well as the writer deletes.
  it "omits an unlabelled domain nothing points at" do
    SendingServiceDomain.create!(domain: "residue.example.com")
    contributing_domain("real.example.com")

    get pipeline_bill_creator_path(bill)

    expect(inertia).to render_component(Pages::BILL_CREATOR)
    shipped = inertia.props[:sending_service_domains].pluck(:domain)
    expect(shipped).to include("real.example.com")
    expect(shipped).not_to include("residue.example.com")
  end

  # An operator's decision stays on screen even when nothing names the domain
  # any more — otherwise a confirmed label could never be taken back.
  it "keeps a labelled domain with no contributions" do
    SendingServiceDomain.create!(domain: "confirmed.example.com", label: SendingServiceDomain::CONFIRMED)

    get pipeline_bill_creator_path(bill)

    expect(inertia).to render_component(Pages::BILL_CREATOR)
    shipped = inertia.props[:sending_service_domains].pluck(:domain)
    expect(shipped).to include("confirmed.example.com")
  end

  # B11's actual security-relevant regression: `domain` is a string lifted out of a From: line in
  # a PDF any member of the public can submit, and the format admits leading digits/hyphens, so
  # `ORDER BY domain LIMIT n` can push the real sending-service domain past the cap where no
  # screen ever reaches it again. This domain sorts LAST alphabetically (it is well past 200
  # "aaaa"-prefixed rows) but carries by far the highest machine-sent count, so it must still be
  # selected — the cap has to rank by the same rule the screen displays by, not by name.
  it "selects the real sending-service domain even when its name sorts after row 200 alphabetically" do
    SendingServiceDomain::MAX_PANEL_ROWS.times do |i|
      contributing_domain_with_counts(
        "aaaa#{i.to_s.rjust(4, "0")}.example.com",
        sender_count: 1, letter_count: 1, machine_sent_letter_count: 0
      )
    end
    contributing_domain_with_counts(
      "zzzz-real-sending-service.example.com",
      sender_count: 50, letter_count: 50, machine_sent_letter_count: 50
    )

    get pipeline_bill_creator_path(bill)

    expect(inertia).to render_component(Pages::BILL_CREATOR)
    shipped = inertia.props[:sending_service_domains].pluck(:domain)
    expect(shipped).to include("zzzz-real-sending-service.example.com")
  end

  it "ships the list ranked by machine-sent count, highest first" do
    contributing_domain_with_counts("low.example.com", sender_count: 1, letter_count: 10, machine_sent_letter_count: 1)
    contributing_domain_with_counts("high.example.com", sender_count: 1, letter_count: 10, machine_sent_letter_count: 9)
    contributing_domain_with_counts("mid.example.com", sender_count: 1, letter_count: 10, machine_sent_letter_count: 5)

    get pipeline_bill_creator_path(bill)

    expect(inertia).to render_component(Pages::BILL_CREATOR)
    shipped = inertia.props[:sending_service_domains]
    ranked = shipped.select { |row| ["low.example.com", "high.example.com", "mid.example.com"].include?(row[:domain]) }
    expect(ranked.pluck(:domain)).to eq(["high.example.com", "mid.example.com", "low.example.com"])
    expect(ranked.pluck(:machine_sent_letter_count)).to eq([9, 5, 1])
  end

  # The eager-load trap named in the fix brief: `.includes` on a relation carrying a GROUP BY can
  # be folded into the same joined+grouped query (eager_load) instead of a separate preload query,
  # and if it were, the loaded association would read as ONE collapsed row per domain instead of
  # one row per contribution — SendingServiceDomainResource#bill_count (`.size` on the loaded
  # association) would then silently ship 1 for every domain, however many bills it really touched.
  it "still reports the real bill_count for a domain that has contributed to more than one bill" do
    # A different release date, not a different locale: bills has a unique index on
    # (scheduled_release_date_utc, sway_locale_id), and the two bills share this spec's locale.
    other_bill = create(:bill, sway_locale: sway_locale, legislator: sway_locale.legislators.first,
      scheduled_release_date_utc: bill.scheduled_release_date_utc + 1.day)
    domain = contributing_domain_with_counts(
      "multi-bill.example.com", sender_count: 1, letter_count: 1, machine_sent_letter_count: 1
    )
    SendingServiceDomainBill.create!(
      sending_service_domain: domain, bill: other_bill,
      sender_count: 2, letter_count: 2, machine_sent_letter_count: 2
    )

    get pipeline_bill_creator_path(bill)

    expect(inertia).to render_component(Pages::BILL_CREATOR)
    shipped = inertia.props[:sending_service_domains].find { |row| row[:domain] == "multi-bill.example.com" }
    expect(shipped[:bill_count]).to eq(2)
    expect(shipped[:sender_count]).to eq(3)
    expect(shipped[:letter_count]).to eq(3)
    expect(shipped[:machine_sent_letter_count]).to eq(3)
  end

  # The trap the fix brief names by name: panel_domains must stay ungrouped so this stays a plain
  # Integer. Chaining .panel_ranked onto panel_domains ITSELF before this count would silently
  # turn it into a Hash (one count per GROUP BY id row) instead of a total.
  it "still ships sending_service_domains_total as a plain Integer" do
    contributing_domain("a.example.com")
    contributing_domain("b.example.com")

    get pipeline_bill_creator_path(bill)

    expect(inertia).to render_component(Pages::BILL_CREATOR)
    expect(inertia.props[:sending_service_domains_total]).to be_a(Integer)
    expect(inertia.props[:sending_service_domains_total]).to eq(2)
  end
end
