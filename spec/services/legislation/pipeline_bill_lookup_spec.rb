# frozen_string_literal: true

require "rails_helper"

# A bill is unique on TWO columns (external_id, sway_locale_id) together —
# alone, external_id doesn't identify one; a lookup treating it as one used
# to grab whichever row came first.
RSpec.describe Legislation::PipelineBillLookup do
  let(:baltimore) { create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states") }
  let(:congress) { create(:sway_locale, city: "congress", state: "congress", country: "united_states") }

  # scheduled_release_date_utc is UNIQUE per (date, sway_locale_id) — the Bill
  # of the Week slot — so same-locale fixtures need distinct dates.
  def bill_in(sway_locale, external_id, released_days_ago: nil)
    create(
      :bill,
      sway_locale: sway_locale,
      external_id: external_id,
      scheduled_release_date_utc: (released_days_ago || external_id.bytes.sum % 500).days.ago
    )
  end

  describe ".find" do
    it "returns the bill when exactly one carries the external_id" do
      bill = bill_in(baltimore, "25-0064")

      expect(described_class.find("25-0064")).to eq(bill)
    end

    it "returns nil when no bill carries the external_id" do
      expect(described_class.find("25-0064")).to be_nil
    end

    # THE CASE THAT HAD TO FAIL FIRST: nothing keeps external_id unique
    # across jurisdictions, so lookups used to settle a clash with whichever
    # row came back.
    it "returns nil rather than an arbitrary row when two locales share the external_id" do
      bill_in(baltimore, "25-0064")
      bill_in(congress, "25-0064")

      expect(described_class.find("25-0064")).to be_nil
    end

    it "warns on the ambiguity so the operator is not left with a silent skip" do
      allow(SwayLogging).to receive(:warn)
      bill_in(baltimore, "25-0064")
      bill_in(congress, "25-0064")

      described_class.find("25-0064")

      expect(SwayLogging).to have_received(:warn).with(/25-0064/)
    end

    it "resolves the collision when the caller knows the run's locale" do
      baltimore_bill = bill_in(baltimore, "25-0064")
      bill_in(congress, "25-0064")

      expect(described_class.find("25-0064", sway_locale_id: baltimore.id)).to eq(baltimore_bill)
    end

    it "returns nil when the locale scope excludes the only match" do
      bill_in(baltimore, "25-0064")

      expect(described_class.find("25-0064", sway_locale_id: congress.id)).to be_nil
    end
  end

  describe ".title_map" do
    it "maps each unambiguous external_id to its title" do
      bill_in(baltimore, "25-0064").update!(title: "An Ordinance")

      expect(described_class.title_map(["25-0064"])).to eq({"25-0064" => "An Ordinance"})
    end

    # The same bug on the display side: the admin per-bill grid showed whichever
    # jurisdiction's title `pluck.to_h` happened to write last.
    it "omits an external_id that two locales share rather than showing one arbitrarily" do
      bill_in(baltimore, "25-0064").update!(title: "Baltimore ordinance")
      bill_in(congress, "25-0064").update!(title: "A completely different federal bill")
      bill_in(baltimore, "25-0065").update!(title: "Unambiguous")

      expect(described_class.title_map(["25-0064", "25-0065"]))
        .to eq({"25-0065" => "Unambiguous"})
    end

    it "issues a single query regardless of how many ids are asked for" do
      bill_in(baltimore, "25-0064")
      bill_in(baltimore, "25-0065")

      queries = 0
      counter = lambda { |_name, _start, _finish, _id, payload|
        queries += 1 unless payload[:name].to_s.in?(["SCHEMA", "TRANSACTION"])
      }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        described_class.title_map(["25-0064", "25-0065"])
      end

      expect(queries).to eq(1)
    end

    it "returns an empty map for no ids without touching the database" do
      expect(described_class.title_map([])).to eq({})
    end
  end

  describe ".run_bills_for" do
    let(:maryland) { create(:sway_locale, city: "maryland", state: "maryland", country: "united_states") }

    it "resolves all-bills runs scoped to the bill's locale even when another locale shares external_id" do
      baltimore_bill = bill_in(baltimore, "SHARED-01")
      maryland_bill = bill_in(maryland, "SHARED-01")

      baltimore_run = create(:legislation_pipeline_run, bill: nil, sway_locale: baltimore)
      maryland_run = create(:legislation_pipeline_run, bill: nil, sway_locale: maryland)

      baltimore_prb = create(
        :pipeline_run_bill,
        legislation_pipeline_run: baltimore_run,
        bill_external_id: "SHARED-01"
      )
      maryland_prb = create(
        :pipeline_run_bill,
        legislation_pipeline_run: maryland_run,
        bill_external_id: "SHARED-01"
      )

      expect(described_class.run_bills_for(baltimore_bill)).to contain_exactly(baltimore_prb)
      expect(described_class.run_bills_for(maryland_bill)).to contain_exactly(maryland_prb)
    end

    it "excludes foreign-locale all-bills runs" do
      baltimore_bill = bill_in(baltimore, "B-01")
      maryland_run = create(:legislation_pipeline_run, bill: nil, sway_locale: maryland)
      create(:pipeline_run_bill, legislation_pipeline_run: maryland_run, bill_external_id: "B-01")

      expect(described_class.run_bills_for(baltimore_bill)).to be_empty
    end
  end
end
