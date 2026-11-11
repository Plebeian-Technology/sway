# frozen_string_literal: true

module OpenLegislatorFixtureHelpers
  VALID_MATTER_OUTCOMES = %w[pending enacted failed withdrawn unknown].freeze
  VALID_ACTION_RESULTS = ["pass", "fail", nil].freeze
  VALID_VOTE_VALUES = %w[yes no abstain absent recused present].freeze
  EXACT_PAGE_KEYS = %w[page last count limit].freeze

  def open_legislator_fixture_files
    Rails.root.glob("spec/fixtures/open_legislator/*.json").map(&:to_s)
  end

  def verify_open_legislator_fixture_invariants!
    fixture_files = open_legislator_fixture_files
    expect(fixture_files.any? { |f| File.basename(f).start_with?("meeting") }).to be(true),
      "Expected spec/fixtures/open_legislator/ to include a meetings fixture"

    fixture_files.each do |file|
      data = JSON.parse(File.read(file))

      if data.is_a?(Hash) && data.key?("data")
        if data["data"].is_a?(Array)
          expect(data.keys).to match_array(%w[data page jurisdiction]),
            "Paginated index fixture #{File.basename(file)} top-level keys #{data.keys} must match [\"data\", \"page\", \"jurisdiction\"]"
          expect(data["page"].keys).to match_array(EXACT_PAGE_KEYS),
            "Fixture #{File.basename(file)} page envelope keys #{data["page"].keys} do not match #{EXACT_PAGE_KEYS}"
        elsif data["data"].is_a?(Hash)
          expect(data.keys).to eq(%w[data]),
            "Single-record show fixture #{File.basename(file)} top-level keys #{data.keys} must be [\"data\"] only"
        end
      end

      check_outcomes(data, file)
      check_action_results(data, file)
      check_vote_values_and_visibility(data, file)
    end
  end

  private

  def check_outcomes(node, file)
    case node
    when Hash
      if node.key?("outcome") && node["outcome"].present?
        expect(VALID_MATTER_OUTCOMES).to include(node["outcome"]),
          "Fixture #{File.basename(file)} contains invalid outcome #{node["outcome"].inspect}; expected one of #{VALID_MATTER_OUTCOMES}"
      end
      node.each_value { |v| check_outcomes(v, file) }
    when Array
      node.each { |item| check_outcomes(item, file) }
    end
  end

  def check_action_results(node, file)
    case node
    when Hash
      if node.key?("result")
        expect(VALID_ACTION_RESULTS).to include(node["result"]),
          "Fixture #{File.basename(file)} contains invalid action result #{node["result"].inspect}; expected one of #{VALID_ACTION_RESULTS}"
      end
      node.each_value { |v| check_action_results(v, file) }
    when Array
      node.each { |item| check_action_results(item, file) }
    end
  end

  def check_vote_values_and_visibility(node, file)
    case node
    when Hash
      if node["votes"].is_a?(Array)
        node["votes"].each do |vote|
          next unless vote.is_a?(Hash)

          expect(VALID_VOTE_VALUES).to include(vote["value"]),
            "Fixture #{File.basename(file)} contains invalid vote value #{vote["value"].inspect}; expected one of #{VALID_VOTE_VALUES}"
        end
      end

      if node.key?("roll_call_recorded") && node.key?("vote_visibility")
        if node["roll_call_recorded"] == true
          expect(node["vote_visibility"]).to eq("recorded"),
            "Fixture #{File.basename(file)} has roll_call_recorded: true but vote_visibility: #{node["vote_visibility"].inspect}"
        elsif node["roll_call_recorded"] == false && node["tally"].is_a?(Hash) && node["tally"].values.any? { |v| !v.nil? }
          expect(node["vote_visibility"]).to eq("tally_only"),
            "Fixture #{File.basename(file)} has roll_call_recorded: false with non-null tally but vote_visibility: #{node["vote_visibility"].inspect}"
        end
      end

      node.each_value { |v| check_vote_values_and_visibility(v, file) }
    when Array
      node.each { |item| check_vote_values_and_visibility(item, file) }
    end
  end
end
