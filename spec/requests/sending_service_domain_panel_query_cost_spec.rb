# frozen_string_literal: true

require "rails_helper"

# B12. SendingServiceDomainResource#sender_count/#letter_count/#machine_sent_letter_count each
# called `sending_service_domain_bills.sum(:col)` for every serialized row — ActiveRecord's
# Relation#calculate has no loaded-records short-circuit, so each one issued real SQL regardless
# of `.includes`. At the 200-row cap that was ~600 SUM statements per render, on a page that polls
# itself every 5 seconds while open, from two separate admin tabs.
#
# The fix moves the three sums into the same query that ranks and caps the list
# (SendingServiceDomain.panel_ranked), so the per-row cost the fix removes is proven here by
# counting statements that touch sending_service_domain_bills at two list sizes and asserting the
# count does not grow with the list — same house pattern as
# spec/requests/mirrored_asset_query_cost_spec.rb.
RSpec.describe "The sending-service domain panel's query cost does not grow with the list", type: :request do
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

  def sending_service_domain_bill_reads
    seen = [] #: Array[String]
    subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      next if /SCHEMA|TRANSACTION/.match?(payload[:name].to_s)

      seen << payload[:sql].to_s
    end
    yield
    ActiveSupport::Notifications.unsubscribe(subscription)
    seen.count { |sql| sql.include?("sending_service_domain_bills") }
  end

  # Own small helper local to this file rather than reusing the other spec's private methods —
  # same shape (measure at two sizes, refuse a round that read nothing), different fixtures.
  # Named distinctly from mirrored_asset_query_cost_spec.rb's own reads_at_two_sizes: a bare
  # spec helper declared in sig-test/ is global, so two specs can't share one name (steep-traps).
  def domain_panel_reads_at_two_sizes(add:, &probe)
    add.call(3, 0)
    small = sending_service_domain_bill_reads(&probe)
    expect(small).to be_positive, "measured no reads of sending_service_domain_bills, so this compares nothing"

    add.call(8, 3)
    [small, sending_service_domain_bill_reads(&probe)]
  end

  def add_contributing_domains(count:, from:)
    count.times do |index|
      n = from + index
      domain = SendingServiceDomain.create!(domain: "panel-cost-#{n.to_s.rjust(4, "0")}.example.com")
      SendingServiceDomainBill.create!(
        sending_service_domain: domain, bill: bill,
        sender_count: 1, letter_count: 2, machine_sent_letter_count: n.even? ? 1 : 0
      )
    end
  end

  it "holds steady on the bill creator's sending-services panel" do
    adder = ->(count, from) { add_contributing_domains(count: count, from: from) }

    small, large = domain_panel_reads_at_two_sizes(add: adder) do
      get "/admin/bill_creator/#{bill.id}/creator"
      expect(response).to have_http_status(:ok)
    end

    expect(large).to eq(small)
  end
end
