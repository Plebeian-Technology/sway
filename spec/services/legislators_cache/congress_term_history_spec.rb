# frozen_string_literal: true

require "rails_helper"

# @lat: [[current-legislator-term#Why a Congress term is rebuilt from published history]]
RSpec.describe LegislatorsCache::CongressTermHistory do
  let(:base_url) { "https://unitedstates.github.io/congress-legislators" }

  def member(bioguide, terms)
    {"id" => {"bioguide" => bioguide}, "terms" => terms}
  end

  def stub_files(current:, historical: [])
    stub_request(:get, "#{base_url}/legislators-current.json")
      .to_return(status: 200, body: current.to_json, headers: {"Content-Type" => "application/json"})
    stub_request(:get, "#{base_url}/legislators-historical.json")
      .to_return(status: 200, body: historical.to_json, headers: {"Content-Type" => "application/json"})
  end

  describe ".fetch" do
    it "reports a House term with the seat it was served in" do
      stub_files(current: [
        member("B001260", [
          {"type" => "rep", "start" => "2023-01-03", "end" => "2025-01-03", "state" => "FL", "district" => 16}
        ])
      ])

      terms = described_class.fetch(["B001260"]).terms_for("B001260")

      expect(terms).to eq([
        {"chamber" => "House of Representatives", "startYear" => 2023, "endYear" => 2025,
         "beganOn" => "2023-01-03", "endedOn" => "2025-01-03", "stateCode" => "FL", "district" => 16}
      ])
    end

    # The reason this source was chosen. congress.gov reports the same six
    # years as three separate two-year entries, and a two-year senate term puts
    # a sitting senator out of office.
    # @lat: [[seed-legislator-title-tests#Configured roster seat mapping#Preserves published Senate class on terms]]
    it "keeps a senate term six years long, names no district, and preserves the Senate class" do
      stub_files(current: [
        member("G000386", [
          {"type" => "sen", "start" => "2023-01-03", "end" => "2029-01-03", "state" => "IA", "class" => 3}
        ])
      ])

      terms = described_class.fetch(["G000386"]).terms_for("G000386")

      expect(terms).to eq([
        {"chamber" => "Senate", "startYear" => 2023, "endYear" => 2029,
         "beganOn" => "2023-01-03", "endedOn" => "2029-01-03", "stateCode" => "IA", "class" => 3}
      ])
    end

    it "preserves the Senate class on Senate terms and omits it on House terms" do
      stub_files(current: [
        member("S000001", [
          {"type" => "sen", "start" => "2025-01-03", "end" => "2031-01-03", "state" => "MD", "class" => 1}
        ]),
        member("H000001", [
          {"type" => "rep", "start" => "2025-01-03", "end" => "2027-01-03", "state" => "MD", "district" => 3, "class" => 1}
        ])
      ])

      history = described_class.fetch(%w[S000001 H000001])
      expect(history.terms_for("S000001").first).to include("chamber" => "Senate", "class" => 1)
      expect(history.terms_for("H000001").first).to include("chamber" => "House of Representatives", "district" => 3)
      expect(history.terms_for("H000001").first).not_to have_key("class")
    end

    it "ensures every state's two sitting 119th Congress Senators carry two distinct classes in {1, 2, 3}" do
      file = Rails.root.join("db", "seeds", "data", "united_states", "congress", "congress", "legislators.json")
      data = JSON.parse(File.read(file))

      sitting_senators = data.select do |m|
        terms = m.dig("terms", "item") || []
        terms.any? { |t| t["chamber"] == "Senate" && t["startYear"] <= 2025 && t["endYear"] >= 2025 }
      end

      expect(sitting_senators.count).to eq(100)

      by_state = sitting_senators.group_by do |m|
        active_term = m["terms"]["item"].find { |t| t["chamber"] == "Senate" && t["startYear"] <= 2025 && t["endYear"] >= 2025 }
        active_term["stateCode"]
      end

      expect(by_state.keys.count).to eq(50)

      by_state.each do |state, members|
        classes = members.map do |m|
          active_term = m["terms"]["item"].find { |t| t["chamber"] == "Senate" && t["startYear"] <= 2025 && t["endYear"] >= 2025 }
          active_term["class"]
        end
        expect(classes.count).to eq(2)
        expect(classes.uniq.count).to eq(2), "Expected state #{state} to have 2 distinct Senate classes, got #{classes.inspect}"
        expect(classes).to all(be_in([1, 2, 3]))
      end

      moody = data.find { |m| m["bioguideId"] == "M001244" }
      moody_term = moody["terms"]["item"].find { |t| t["chamber"] == "Senate" && t["startYear"] <= 2025 && t["endYear"] >= 2025 }
      expect(moody_term["class"]).to eq(3)

      husted = data.find { |m| m["bioguideId"] == "H001104" }
      husted_term = husted["terms"]["item"].find { |t| t["chamber"] == "Senate" && t["startYear"] <= 2025 && t["endYear"] >= 2025 }
      expect(husted_term["class"]).to eq(3)
    end

    # @lat: [[legislators-cache-congress-term-history#Why the real end day rides along beside the widened years]]
    it "carries the day a term really ended, alongside the widened years" do
      stub_files(current: [
        member("G000359", [
          {"type" => "sen", "start" => "2021-01-03", "end" => "2026-07-11", "state" => "SC", "class" => 2}
        ])
      ])

      terms = described_class.fetch(["G000359"]).terms_for("G000359")

      expect(terms.first["endedOn"]).to eq("2026-07-11")
      # The years still say 2027, because that is the handover Sway can express.
      # The date is what tells the truth about the eleventh of July.
      expect(terms.first["endYear"]).to eq(2027)
    end

    # A senator appointed until a special election in November 2026. Rounding
    # the end DOWN to 2026 would say the seat changed hands in January,
    # ousting a sitting senator eleven months early.
    it "runs a term that ends late in the year on to the next January" do
      stub_files(current: [
        member("H001104", [
          {"type" => "sen", "start" => "2025-01-21", "end" => "2026-11-03", "state" => "OH"}
        ])
      ])

      terms = described_class.fetch(["H001104"]).terms_for("H001104")

      expect(terms.first).to include("startYear" => 2025, "endYear" => 2027)
      # An appointee's real start — the years alone would seat him January 3rd.
      expect(terms.first["beganOn"]).to eq("2025-01-21")
    end

    # Adam Schiff was a House member through 2024, then a senator for the
    # last three weeks. Both widen to windows ending January 2025, misfiling
    # his House vote under the Senate.
    it "drops a short term that sits wholly inside a longer one" do
      stub_files(current: [
        member("S001150", [
          {"type" => "rep", "start" => "2023-01-03", "end" => "2024-12-08", "state" => "CA", "district" => 30},
          {"type" => "sen", "start" => "2024-12-09", "end" => "2025-01-03", "state" => "CA"},
          {"type" => "sen", "start" => "2025-01-03", "end" => "2031-01-03", "state" => "CA"}
        ])
      ])

      terms = described_class.fetch(["S001150"]).terms_for("S001150")

      expect(terms.pluck("startYear")).to eq([2023, 2025])
      expect(terms.first).to include("chamber" => "House of Representatives", "district" => 30)
    end

    it "reports terms oldest first" do
      stub_files(current: [
        member("A000001", [
          {"type" => "rep", "start" => "2025-01-03", "end" => "2027-01-03", "state" => "MD", "district" => 3},
          {"type" => "rep", "start" => "2021-01-03", "end" => "2023-01-03", "state" => "MD", "district" => 3},
          {"type" => "rep", "start" => "2023-01-03", "end" => "2025-01-03", "state" => "MD", "district" => 3}
        ])
      ])

      terms = described_class.fetch(["A000001"]).terms_for("A000001")

      expect(terms.pluck("startYear")).to eq([2021, 2023, 2025])
    end

    # The historical file is 13 MB and Sway runs on one small machine, so it is
    # only read when the current one leaves somebody unanswered.
    it "does not read the historical file when the current one answers for everybody" do
      stub_files(current: [
        member("A000001", [
          {"type" => "rep", "start" => "2023-01-03", "end" => "2025-01-03", "state" => "MD", "district" => 3}
        ])
      ])

      described_class.fetch(["A000001"])

      expect(WebMock).not_to have_requested(:get, "#{base_url}/legislators-historical.json")
    end

    # Somebody who has left Congress since the roster was fetched. The current
    # file no longer carries them; the historical one does.
    it "reads the historical file for anyone the current one does not answer for" do
      stub_files(
        current: [member("A000001", [
          {"type" => "rep", "start" => "2023-01-03", "end" => "2025-01-03", "state" => "MD", "district" => 3}
        ])],
        historical: [member("G000359", [
          {"type" => "sen", "start" => "2021-01-03", "end" => "2026-07-11", "state" => "SC"}
        ])]
      )

      history = described_class.fetch(%w[A000001 G000359])

      expect(history.terms_for("G000359").first).to include("startYear" => 2021, "endYear" => 2027)
      expect(history.missing).to be_empty
    end

    it "names anyone neither file knows, so a stale source is a number and not a silence" do
      stub_files(current: [], historical: [])

      history = described_class.fetch(%w[Z000999 A000001])

      expect(history.missing).to eq(%w[A000001 Z000999])
      expect(history.terms_for("Z000999")).to be_nil
    end

    # @lat: [[current-legislator-term#Why a Congress term is rebuilt from published history]]
    it "answers for nobody whose record carries a date it cannot read" do
      stub_files(
        current: [
          member("A000001", [
            {"type" => "rep", "start" => "not-a-date", "end" => "2023-01-03", "state" => "MD", "district" => 3},
            {"type" => "rep", "start" => "2023-01-03", "end" => "2025-01-03", "state" => "MD", "district" => 3}
          ])
        ],
        historical: []
      )

      history = described_class.fetch(["A000001"])

      expect(history.terms_for("A000001")).to be_nil
      expect(history.missing).to eq(["A000001"])
    end

    it "still answers for everybody whose record reads whole" do
      stub_files(current: [
        member("A000001", [
          {"type" => "rep", "start" => "2021-01-03", "end" => "2023-01-03", "state" => "MD", "district" => 3},
          {"type" => "rep", "start" => "2023-01-03", "end" => "2025-01-03", "state" => "MD", "district" => 3}
        ])
      ])

      terms = described_class.fetch(["A000001"]).terms_for("A000001")

      expect(terms.pluck("startYear")).to eq([2021, 2023])
    end

    # Failing loudly is the safe direction: the caller writes the roster file,
    # and a roster written without term history would quietly undo this work.
    it "raises when the source answers with an error" do
      stub_request(:get, "#{base_url}/legislators-current.json").to_return(status: 503, body: "down")

      expect { described_class.fetch(["A000001"]) }
        .to raise_error(described_class::FetchError, /503/)
    end
  end
end
