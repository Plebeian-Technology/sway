# frozen_string_literal: true

# == Schema Information
#
# Table name: admin_settings
# Database name: primary
#
#  id                              :integer          not null, primary key
#  classification_model            :string           default("claude-haiku-4-5-20251001"), not null
#  classification_reasoning_effort :string
#  decision_model                  :string           default("ScaleDown Classify Latest"), not null
#  extraction_model                :string           default("ScaleDown Extract Latest"), not null
#  offered_models                  :json
#  summarization_model             :string           not null
#  summarization_reasoning_effort  :string
#  summary_batch_chunk_size        :integer          default(25), not null
#  summary_batch_enabled           :boolean          default(FALSE), not null
#  created_at                      :datetime         not null
#  updated_at                      :datetime         not null
#  updated_by_id                   :integer
#
# Indexes
#
#  index_admin_settings_on_updated_by_id  (updated_by_id)
#
# Foreign Keys
#
#  updated_by_id  (updated_by_id => users.id)
#
require "rails_helper"

# A model with exactly one row, holding the Claude model an admin has picked.
# SUPPORTED_MODELS is a frozen list of three allowed names, and validation
# rejects anything not on it. That single row is reached through .singleton,
# which uses first_or_create!.
RSpec.describe AdminSetting do
  describe "SUPPORTED_MODELS allowlist (R6)" do
    it "is a frozen Array containing the twelve baseline models" do
      expect(described_class::SUPPORTED_MODELS).to eq(
        [
          "claude-haiku-5-5",
          "claude-sonnet-5-5",
          "claude-opus-5-5",
          "Opus Latest",
          "Sonnet Latest",
          "Haiku Latest",
          "Gemini Argon Latest",
          "Gemini Flash Latest",
          "GLM Latest",
          "Deepseek Pro Latest",
          "Deepseek Flash Latest",
          "OpenRouter Auto"
        ]
      )
      expect(described_class::SUPPORTED_MODELS).to be_frozen
    end

    it "is a frozen Hash mapping all twelve baseline models to friendly labels" do
      expect(described_class::SUPPORTED_MODEL_LABELS).to eq(
        {
          "claude-haiku-5-5" => "Haiku 5.5",
          "claude-sonnet-5-5" => "Sonnet 5.5",
          "claude-opus-5-5" => "Opus 5.5",
          "Opus Latest" => "Opus Latest",
          "Sonnet Latest" => "Sonnet Latest",
          "Haiku Latest" => "Haiku Latest",
          "Gemini Argon Latest" => "Gemini Argon Latest",
          "Gemini Flash Latest" => "Gemini Flash Latest",
          "GLM Latest" => "GLM Latest",
          "Deepseek Pro Latest" => "Deepseek Pro Latest",
          "Deepseek Flash Latest" => "Deepseek Flash Latest",
          "OpenRouter Auto" => "OpenRouter Auto"
        }
      )
      expect(described_class::SUPPORTED_MODEL_LABELS).to be_frozen
    end

    # AdminSetting is now strictly one row: create! fails once the table has one.
    # So the allowed-value and presence checks below run the validations by
    # calling update! on that row.
    it "accepts every supported model as a valid summarization_model" do
      described_class::SUPPORTED_MODELS.each do |model|
        expect {
          described_class.singleton.update!(summarization_model: model)
        }.not_to raise_error
      end
    end

    it "rejects non-allowlisted models (e.g. gpt-4)" do
      expect {
        described_class.singleton.update!(summarization_model: "gpt-4")
      }.to raise_error(ActiveRecord::RecordInvalid, /summarization model/i)
    end

    it "rejects nil / blank" do
      expect {
        described_class.singleton.update!(summarization_model: "")
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  # @lat: [[admin-setting-model-list#Why AdminSetting enforces its own one-row rule twice]]
  describe "classification_model" do
    it "defaults to Haiku — the tier the classifier was pinned to" do
      expect(described_class.singleton.classification_model).to eq("claude-haiku-5-5")
    end

    it "accepts every model on the shared allowlist" do
      described_class::SUPPORTED_MODELS.each do |model|
        expect {
          described_class.singleton.update!(classification_model: model)
        }.not_to raise_error
      end
    end

    it "rejects non-allowlisted models" do
      expect {
        described_class.singleton.update!(classification_model: "gpt-4")
      }.to raise_error(ActiveRecord::RecordInvalid, /classification model/i)
    end

    it "rejects blank" do
      expect {
        described_class.singleton.update!(classification_model: "")
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    # This is why the column is separate. If the two ever shared storage, an
    # operator raising summary quality would quietly change the price of every
    # classification call — exactly what pinning the model was meant to prevent.
    it "moves independently of summarization_model" do
      setting = described_class.singleton
      setting.update!(summarization_model: "claude-opus-5-5")

      expect(setting.reload.classification_model).to eq("claude-haiku-5-5")

      setting.update!(classification_model: "claude-sonnet-5-5")
      expect(setting.reload.summarization_model).to eq("claude-opus-5-5")
    end
  end

  # @lat: [[admin-setting-model-list#Why the inclusion validations are conditional]]
  describe "a stored model that is no longer on the list" do
    let(:retired_model) { "claude-sonnet-4-6" }

    let(:setting) do
      row = described_class.singleton
      row.update_column(:summarization_model, retired_model)
      row.reload
    end

    it "lets the operator change the OTHER column" do
      expect { setting.update!(classification_model: "claude-sonnet-5-5") }.not_to raise_error
      expect(setting.reload.classification_model).to eq("claude-sonnet-5-5")
    end

    it "lets the operator replace the retired name itself" do
      expect { setting.update!(summarization_model: "claude-sonnet-5-5") }.not_to raise_error
      expect(setting.reload.summarization_model).to eq("claude-sonnet-5-5")
    end

    it "leaves the retired name in place until somebody replaces it" do
      setting.update!(classification_model: "claude-sonnet-5-5")

      expect(setting.reload.summarization_model).to eq(retired_model)
    end

    # The guard still does the work it was written for. Only a value that MOVED
    # is checked, and a name arriving from a request has moved.
    it "still refuses a name that is not on the list" do
      expect { setting.update!(summarization_model: "gpt-4") }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    it "still checks both columns on a brand-new row" do
      described_class.delete_all

      expect {
        described_class.create!(summarization_model: "gpt-4", classification_model: "gpt-4")
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  # Only one row is ever allowed in this table, whatever its summarization_model
  # says. The migration's seed code guards that at setup time; this validation
  # guards it at runtime, for any other code that tries to create! a new row.
  describe "singleton enforcement" do
    it "rejects AdminSetting.create! when a row already exists" do
      described_class.singleton # ensure the singleton row exists in this test
      expect {
        described_class.create!(summarization_model: "claude-sonnet-5-5")
      }.to raise_error(ActiveRecord::RecordInvalid, /singleton/i)
    end

    it "allows AdminSetting.create! on a truly empty table (fresh DB / seed path)" do
      described_class.delete_all
      expect {
        described_class.create!(summarization_model: "claude-haiku-5-5")
      }.not_to raise_error
      expect(described_class.count).to eq(1)
    end
  end

  describe ".singleton" do
    it "returns the seeded row on a freshly migrated DB" do
      expect(described_class.singleton.summarization_model).to eq("claude-haiku-5-5")
    end

    it "returns the same row on consecutive calls (no double-insert)" do
      first = described_class.singleton
      second = described_class.singleton
      expect(first.id).to eq(second.id)
      expect(described_class.count).to eq(1)
    end

    it "is mutable mid-run; subsequent reads see the new value (R7 prerequisite)" do
      described_class.singleton.update!(summarization_model: "claude-sonnet-5-5")
      expect(described_class.singleton.summarization_model).to eq("claude-sonnet-5-5")
    end

    # @lat: [[admin-setting-model-list#Why the seed uses first_or_create!, not find_or_create_by!]]
    it "does not insert a duplicate row when migration seed replays post-admin-upgrade" do
      # The admin has already switched the row to Sonnet.
      described_class.singleton.update!(summarization_model: "claude-sonnet-5-5")
      expect(described_class.count).to eq(1)

      # The replay, running the same code as
      # db/migrate/20260528000001_create_admin_settings.rb lines 38-39.
      described_class.reset_column_information
      described_class.first_or_create!(summarization_model: "claude-haiku-5-5")

      expect(described_class.count).to eq(1)
      expect(described_class.singleton.summarization_model).to eq("claude-sonnet-5-5")
    end
  end

  describe "belongs_to :updated_by (optional)" do
    # Because only one row may exist, these use update! on the seeded row rather
    # than create! a second one.
    it "allows updated_by_user_id to be nil (seeded row carries no provenance)" do
      expect(described_class.singleton.updated_by).to be_nil
    end

    it "accepts a User as updated_by" do
      user = create(:user)
      described_class.singleton.update!(summarization_model: "claude-sonnet-5-5", updated_by: user)
      expect(described_class.singleton.updated_by_id).to eq(user.id)
    end
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#What decides how many batches a run submits]]
  describe "summary_batch_chunk_size" do
    it "seeds at the documented default, so a run chunks without anyone setting it" do
      expect(described_class.singleton.summary_batch_chunk_size)
        .to eq(described_class::SUMMARY_BATCH_CHUNK_SIZE_DEFAULT)
    end

    it "accepts a value an operator can change without a deploy" do
      described_class.singleton.update!(summary_batch_chunk_size: 50)

      expect(described_class.singleton.reload.summary_batch_chunk_size).to eq(50)
    end

    it "refuses zero, which would ask each_slice for an empty chunk" do
      setting = described_class.singleton
      setting.summary_batch_chunk_size = 0

      expect(setting).not_to be_valid
    end

    it "refuses a negative chunk size" do
      setting = described_class.singleton
      setting.summary_batch_chunk_size = -1

      expect(setting).not_to be_valid
    end

    it "accepts the largest chunk the ceiling allows" do
      setting = described_class.singleton
      setting.summary_batch_chunk_size = 100

      expect(setting).to be_valid
    end

    it "refuses a chunk past the ceiling, which would build one request the API answers with a 400" do
      setting = described_class.singleton
      setting.summary_batch_chunk_size = 101

      expect(setting).not_to be_valid
    end
  end

  describe "#offered_models_list" do
    let(:setting) { described_class.singleton }

    it "defaults to SUPPORTED_MODELS when offered_models is nil" do
      setting.update_column(:offered_models, nil)
      expect(setting.offered_models_list).to eq(described_class::SUPPORTED_MODELS)
    end

    it "defaults to SUPPORTED_MODELS when offered_models is empty array" do
      setting.update_column(:offered_models, [])
      expect(setting.offered_models_list).to eq(described_class::SUPPORTED_MODELS)
    end

    it "defaults to SUPPORTED_MODELS when offered_models contains only blank strings" do
      setting.update_column(:offered_models, ["", "   "])
      expect(setting.offered_models_list).to eq(described_class::SUPPORTED_MODELS)
    end

    it "returns normalized strings when offered_models is populated" do
      setting.update_column(:offered_models, [" openai/gpt-4o ", "meta-llama/llama-3-70b", "openai/gpt-4o", ""])
      expect(setting.offered_models_list).to eq(["openai/gpt-4o", "meta-llama/llama-3-70b"])
    end

    it "returns a dup so mutations do not mutate SUPPORTED_MODELS" do
      setting.update_column(:offered_models, nil)
      list = setting.offered_models_list
      list << "mutated-model"
      expect(described_class::SUPPORTED_MODELS).not_to include("mutated-model")
    end
  end

  describe ".offered_models" do
    it "defaults to SUPPORTED_MODELS on an empty table without creating a row" do
      described_class.delete_all
      expect(described_class.offered_models).to eq(described_class::SUPPORTED_MODELS)
      expect(described_class.count).to eq(0)
    end

    it "defaults to SUPPORTED_MODELS when singleton row exists but offered_models is nil" do
      described_class.singleton.update_column(:offered_models, nil)
      expect(described_class.offered_models).to eq(described_class::SUPPORTED_MODELS)
    end

    it "returns custom offered_models from singleton row when populated" do
      described_class.singleton.update_column(:offered_models, ["custom/model-a", "custom/model-b"])
      expect(described_class.offered_models).to eq(["custom/model-a", "custom/model-b"])
    end

    it "rescues database errors and falls back to SUPPORTED_MODELS" do
      allow(described_class).to receive(:first).and_raise(ActiveRecord::StatementInvalid.new("DB error"))
      expect(described_class.offered_models).to eq(described_class::SUPPORTED_MODELS)
    end
  end

  describe ".offered_model_labels" do
    it "resolves curated labels from SUPPORTED_MODEL_LABELS for baseline models" do
      labels = described_class.offered_model_labels
      expect(labels["claude-haiku-5-5"]).to eq("Haiku 5.5")
      expect(labels["OpenRouter Auto"]).to eq("OpenRouter Auto")
    end

    it "merges cached labels from Llm::OpenRouterModelsService.call" do
      allow(Llm::OpenRouterModelsService).to receive(:call).and_return(
        [
          {id: "openai/gpt-4o", label: "OpenAI: GPT-4o", supports_reasoning: false}
        ]
      )
      labels = described_class.offered_model_labels
      expect(labels["openai/gpt-4o"]).to eq("OpenAI: GPT-4o")
    end

    it "gives precedence to SUPPORTED_MODEL_LABELS when an ID collides" do
      allow(Llm::OpenRouterModelsService).to receive(:call).and_return(
        [
          {id: "OpenRouter Auto", label: "Upstream Auto Label", supports_reasoning: false}
        ]
      )
      labels = described_class.offered_model_labels
      expect(labels["OpenRouter Auto"]).to eq("OpenRouter Auto")
    end

    it "falls back to the model identifier string when neither curated nor cached label exists" do
      described_class.singleton.update_column(:offered_models, ["custom/unlabeled-model"])
      allow(Llm::OpenRouterModelsService).to receive(:call).and_return([])

      labels = described_class.offered_model_labels
      expect(labels["custom/unlabeled-model"]).to eq("custom/unlabeled-model")
    end
  end

  describe ".stored_model?" do
    it "returns false for nil or blank model strings" do
      expect(described_class.stored_model?(nil)).to be false
      expect(described_class.stored_model?("")).to be false
      expect(described_class.stored_model?("   ")).to be false
    end

    it "returns true for any model in offered_models" do
      expect(described_class.stored_model?("claude-haiku-5-5")).to be true
      expect(described_class.stored_model?("OpenRouter Auto")).to be true
    end

    it "returns true for an active summarization_model even if not in offered_models" do
      setting = described_class.singleton
      setting.update_column(:summarization_model, "retired-legacy-model")
      setting.update_column(:offered_models, ["claude-haiku-5-5"])

      expect(described_class.stored_model?("retired-legacy-model")).to be true
    end

    it "returns true for an active classification_model even if not in offered_models" do
      setting = described_class.singleton
      setting.update_column(:classification_model, "legacy-classifier")
      setting.update_column(:offered_models, ["claude-haiku-5-5"])

      expect(described_class.stored_model?("legacy-classifier")).to be true
    end

    it "returns false for an unrecognized model that is neither offered nor active" do
      expect(described_class.stored_model?("unknown/non-existent-model")).to be false
    end

    it "rescues ActiveRecord::StatementInvalid and returns false" do
      allow(described_class).to receive(:offered_models).and_raise(ActiveRecord::StatementInvalid.new("DB error"))
      expect(described_class.stored_model?("claude-haiku-5-5")).to be false
    end
  end

  describe "#add_offered_model!" do
    let(:setting) { described_class.singleton }
    let(:admin_user) { create(:user) }

    it "adds a model recognized by Llm::OpenRouterModelsService.lookup" do
      allow(Llm::OpenRouterModelsService).to receive(:lookup)
        .with("openai/gpt-4o")
        .and_return({id: "openai/gpt-4o", label: "GPT-4o", supports_reasoning: false})

      setting.add_offered_model!("openai/gpt-4o", updated_by: admin_user)

      expect(setting.reload.offered_models_list).to include("openai/gpt-4o")
      expect(setting.updated_by_id).to eq(admin_user.id)
    end

    it "adds a baseline model from SUPPORTED_MODELS without querying OpenRouterModelsService" do
      setting.update_column(:offered_models, ["claude-haiku-5-5"])

      setting.add_offered_model!("Opus Latest")

      expect(setting.reload.offered_models_list).to include("Opus Latest")
    end

    it "is idempotent when the model is already in offered_models_list" do
      setting.update_column(:offered_models, ["claude-haiku-5-5", "claude-sonnet-5-5"])

      setting.add_offered_model!("claude-sonnet-5-5")

      expect(setting.reload.offered_models_list).to eq(["claude-haiku-5-5", "claude-sonnet-5-5"])
    end

    it "rejects an unrecognized model not in SUPPORTED_MODELS or OpenRouterModelsService" do
      allow(Llm::OpenRouterModelsService).to receive(:lookup).with("unknown/fake-model").and_return(nil)

      expect {
        setting.add_offered_model!("unknown/fake-model")
      }.to raise_error(ActiveRecord::RecordInvalid, /is not a recognized OpenRouter model/i)
    end

    it "locks the row around the offered_models read-modify-write" do
      expect(setting).to receive(:with_lock).and_call_original

      setting.add_offered_model!("Opus Latest")
    end

    it "rejects blank model ids" do
      expect {
        setting.add_offered_model!("")
      }.to raise_error(ActiveRecord::RecordInvalid, /is not a recognized OpenRouter model/i)
    end
  end

  describe "#remove_offered_model!" do
    let(:setting) { described_class.singleton }
    let(:admin_user) { create(:user) }

    before do
      setting.update!(
        summarization_model: "claude-haiku-5-5",
        classification_model: "claude-haiku-5-5",
        offered_models: ["claude-haiku-5-5", "Sonnet Latest", "Opus Latest"]
      )
    end

    it "removes an unselected model from offered_models" do
      setting.remove_offered_model!("Sonnet Latest", updated_by: admin_user)

      expect(setting.reload.offered_models_list).to eq(["claude-haiku-5-5", "Opus Latest"])
      expect(setting.updated_by_id).to eq(admin_user.id)
    end

    it "locks the row before checking active models and writing offered_models" do
      expect(setting).to receive(:with_lock).and_call_original

      setting.remove_offered_model!("Sonnet Latest", updated_by: admin_user)
    end

    it "refuses to remove the currently active summarization_model" do
      expect {
        setting.remove_offered_model!("claude-haiku-5-5")
      }.to raise_error(ActiveRecord::RecordInvalid, /cannot remove a model that is currently active/i)
    end

    it "refuses to remove the currently active classification_model" do
      setting.update!(
        summarization_model: "Sonnet Latest",
        classification_model: "claude-haiku-5-5"
      )

      expect {
        setting.remove_offered_model!("claude-haiku-5-5")
      }.to raise_error(ActiveRecord::RecordInvalid, /cannot remove a model that is currently active/i)
    end

    it "refuses to remove the last offered model" do
      setting.update_columns(
        summarization_model: "other-model",
        classification_model: "other-model",
        offered_models: ["Opus Latest"]
      )

      expect {
        setting.remove_offered_model!("Opus Latest")
      }.to raise_error(ActiveRecord::RecordInvalid, /cannot remove the last offered model/i)
    end

    it "refuses to remove a model that is not in offered_models_list" do
      expect {
        setting.remove_offered_model!("unknown-unoffered-model")
      }.to raise_error(ActiveRecord::RecordInvalid, /is not in the offered models list/i)
    end
  end

  describe "dynamic validation against offered_models" do
    let(:setting) { described_class.singleton }

    it "permits setting summarization_model to a dynamically added model" do
      setting.update_column(:offered_models, ["claude-haiku-5-5", "openai/gpt-4o"])

      expect {
        setting.update!(summarization_model: "openai/gpt-4o")
      }.not_to raise_error

      expect(setting.reload.summarization_model).to eq("openai/gpt-4o")
    end

    it "permits setting classification_model to a dynamically added model" do
      setting.update_column(:offered_models, ["claude-haiku-5-5", "openai/gpt-4o"])

      expect {
        setting.update!(classification_model: "openai/gpt-4o")
      }.not_to raise_error

      expect(setting.reload.classification_model).to eq("openai/gpt-4o")
    end

    it "refuses setting summarization_model to a model not in offered_models" do
      setting.update_column(:offered_models, ["claude-haiku-5-5"])

      expect {
        setting.update!(summarization_model: "Opus Latest")
      }.to raise_error(ActiveRecord::RecordInvalid, /summarization model/i)
    end
  end

  describe "reasoning effort settings" do
    let(:setting) { described_class.singleton }

    it "defines REASONING_EFFORTS as low, medium, and high" do
      expect(described_class::REASONING_EFFORTS).to eq(%w[low medium high])
      expect(described_class::REASONING_EFFORTS).to be_frozen
    end

    it "allows nil or valid reasoning effort for summarization and classification" do
      setting.update!(
        summarization_model: "Opus Latest",
        classification_model: "Gemini Argon Latest"
      )

      %w[low medium high].each do |level|
        setting.update!(
          summarization_reasoning_effort: level,
          classification_reasoning_effort: level
        )
        expect(setting.reload.summarization_reasoning_effort).to eq(level)
        expect(setting.reload.classification_reasoning_effort).to eq(level)
      end

      setting.update!(
        summarization_reasoning_effort: nil,
        classification_reasoning_effort: nil
      )
      expect(setting.reload.summarization_reasoning_effort).to be_nil
      expect(setting.reload.classification_reasoning_effort).to be_nil
    end

    it "normalizes blank string to nil before validation" do
      setting.update!(
        summarization_reasoning_effort: "",
        classification_reasoning_effort: "   "
      )
      expect(setting.reload.summarization_reasoning_effort).to be_nil
      expect(setting.reload.classification_reasoning_effort).to be_nil
    end

    it "rejects invalid reasoning effort values" do
      setting.update!(
        summarization_model: "Opus Latest",
        classification_model: "Gemini Argon Latest"
      )

      expect {
        setting.update!(summarization_reasoning_effort: "ultra")
      }.to raise_error(ActiveRecord::RecordInvalid, /summarization reasoning effort/i)

      expect {
        setting.update!(classification_reasoning_effort: "maximum")
      }.to raise_error(ActiveRecord::RecordInvalid, /classification reasoning effort/i)
    end

    it "clears summarization_reasoning_effort to nil when summarization_model does not support reasoning" do
      setting.update!(
        summarization_model: "Opus Latest",
        summarization_reasoning_effort: "high"
      )
      expect(setting.reload.summarization_reasoning_effort).to eq("high")

      setting.update!(summarization_model: "claude-haiku-5-5")
      expect(setting.reload.summarization_reasoning_effort).to be_nil
    end

    it "clears summarization_reasoning_effort when assigned concurrently with a non-reasoning model" do
      setting.update!(
        summarization_model: "claude-haiku-5-5",
        summarization_reasoning_effort: "high"
      )
      expect(setting.reload.summarization_reasoning_effort).to be_nil
    end

    it "clears classification_reasoning_effort to nil when classification_model does not support reasoning" do
      setting.update!(
        classification_model: "Opus Latest",
        classification_reasoning_effort: "medium"
      )
      expect(setting.reload.classification_reasoning_effort).to eq("medium")

      setting.update!(classification_model: "claude-haiku-5-5")
      expect(setting.reload.classification_reasoning_effort).to be_nil
    end

    it "clears classification_reasoning_effort when assigned concurrently with a non-reasoning model" do
      setting.update!(
        classification_model: "claude-haiku-5-5",
        classification_reasoning_effort: "medium"
      )
      expect(setting.reload.classification_reasoning_effort).to be_nil
    end

    it "clears reasoning effort when assigned a dynamic OpenRouter model with supports_reasoning: false" do
      allow(Llm::OpenRouterModelsService).to receive(:lookup)
        .with("openai/gpt-4o")
        .and_return({id: "openai/gpt-4o", label: "GPT-4o", supports_reasoning: false})

      setting.update!(
        offered_models: setting.offered_models_list + ["openai/gpt-4o"],
        summarization_model: "Opus Latest",
        summarization_reasoning_effort: "high",
        classification_model: "Opus Latest",
        classification_reasoning_effort: "low"
      )
      expect(setting.reload.summarization_reasoning_effort).to eq("high")
      expect(setting.reload.classification_reasoning_effort).to eq("low")

      setting.update!(
        summarization_model: "openai/gpt-4o",
        classification_model: "openai/gpt-4o"
      )
      expect(setting.reload.summarization_reasoning_effort).to be_nil
      expect(setting.reload.classification_reasoning_effort).to be_nil
    end

    it "clears classification_reasoning_effort to nil when classification_model is set to a decision model slug or alias" do
      custom_model = {id: "~typesafe/jev-v2", label: "Jev v2", supports_reasoning: false, mode: :decision}
      allow(Llm::OpenRouterModelsService).to receive(:decision_models).and_return([custom_model])
      allow(Llm::OpenRouterModelsService).to receive(:lookup).with("~typesafe/jev-v2").and_return(nil)

      setting.add_offered_model!("~typesafe/jev-v2")
      setting.update!(
        classification_model: "Opus Latest",
        classification_reasoning_effort: "medium"
      )
      expect(setting.reload.classification_reasoning_effort).to eq("medium")

      setting.update!(classification_model: "ScaleDown Classify Latest")
      expect(setting.reload.classification_reasoning_effort).to be_nil

      setting.update!(
        classification_model: "Opus Latest",
        classification_reasoning_effort: "low"
      )
      expect(setting.reload.classification_reasoning_effort).to eq("low")

      setting.update!(classification_model: "~typesafe/jev-v2")
      expect(setting.reload.classification_reasoning_effort).to be_nil
    end
  end

  describe "specialized decision and extraction models" do
    let(:setting) { described_class.singleton }

    describe "constants" do
      it "defines SUPPORTED_DECISION_MODELS as a frozen array of specialized decision models" do
        expect(described_class::SUPPORTED_DECISION_MODELS).to eq(
          [
            "ScaleDown Classify Latest",
            "Jev Latest",
            "Perplexity Decider Latest",
            "Perplexity Decider Flash Latest"
          ]
        )
        expect(described_class::SUPPORTED_DECISION_MODELS).to be_frozen
      end

      it "defines SUPPORTED_DECISION_MODEL_LABELS as a frozen hash" do
        expect(described_class::SUPPORTED_DECISION_MODEL_LABELS).to eq(
          {
            "ScaleDown Classify Latest" => "ScaleDown Classify Latest",
            "Jev Latest" => "Jev Latest",
            "Perplexity Decider Latest" => "Perplexity Decider Latest",
            "Perplexity Decider Flash Latest" => "Perplexity Decider Flash Latest"
          }
        )
        expect(described_class::SUPPORTED_DECISION_MODEL_LABELS).to be_frozen
      end

      it "defines SUPPORTED_EXTRACTION_MODELS as a frozen array containing ScaleDown Extract Latest" do
        expect(described_class::SUPPORTED_EXTRACTION_MODELS).to eq(["ScaleDown Extract Latest"])
        expect(described_class::SUPPORTED_EXTRACTION_MODELS).to be_frozen
      end

      it "defines SUPPORTED_EXTRACTION_MODEL_LABELS as a frozen hash" do
        expect(described_class::SUPPORTED_EXTRACTION_MODEL_LABELS).to eq(
          {"ScaleDown Extract Latest" => "ScaleDown Extract Latest"}
        )
        expect(described_class::SUPPORTED_EXTRACTION_MODEL_LABELS).to be_frozen
      end

      it "leaves SUPPORTED_MODELS strictly as the twelve baseline chat models" do
        expect(described_class::SUPPORTED_MODELS.length).to eq(12)
        expect(described_class::SUPPORTED_MODELS).not_to include("ScaleDown Classify Latest")
        expect(described_class::SUPPORTED_MODELS).not_to include("ScaleDown Extract Latest")
      end
    end

    describe "singleton defaults" do
      it "seeds decision_model with ScaleDown Classify Latest and extraction_model with ScaleDown Extract Latest" do
        expect(setting.decision_model).to eq("ScaleDown Classify Latest")
        expect(setting.extraction_model).to eq("ScaleDown Extract Latest")
      end
    end

    describe "decision_model validations" do
      it "accepts all models in SUPPORTED_DECISION_MODELS" do
        described_class::SUPPORTED_DECISION_MODELS.each do |model|
          expect {
            setting.update!(decision_model: model)
          }.not_to raise_error
          expect(setting.reload.decision_model).to eq(model)
        end
      end

      it "accepts dynamic decision models when present in offered_models" do
        custom_model = {id: "custom/decision-1", label: "Custom Decision 1", supports_reasoning: false, mode: :decision}
        allow(Llm::OpenRouterModelsService).to receive(:decision_models).and_return([custom_model])

        setting.update_column(:offered_models, setting.offered_models_list + ["custom/decision-1"])

        expect {
          setting.update!(decision_model: "custom/decision-1")
        }.not_to raise_error
        expect(setting.reload.decision_model).to eq("custom/decision-1")
      end

      it "rejects blank or unoffered values when decision_model changes" do
        expect {
          setting.update!(decision_model: "")
        }.to raise_error(ActiveRecord::RecordInvalid, /decision model/i)

        expect {
          setting.update!(decision_model: "unsupported/random-model")
        }.to raise_error(ActiveRecord::RecordInvalid, /decision model/i)
      end
    end

    describe "extraction_model validations" do
      it "accepts ScaleDown Extract Latest" do
        expect {
          setting.update!(extraction_model: "ScaleDown Extract Latest")
        }.not_to raise_error
        expect(setting.reload.extraction_model).to eq("ScaleDown Extract Latest")
      end

      it "accepts offered chat and extraction models" do
        expect {
          setting.update!(extraction_model: "Opus Latest")
        }.not_to raise_error
        expect(setting.reload.extraction_model).to eq("Opus Latest")
      end

      it "rejects blank or unoffered values when extraction_model changes" do
        expect {
          setting.update!(extraction_model: "")
        }.to raise_error(ActiveRecord::RecordInvalid, /extraction model/i)

        expect {
          setting.update!(extraction_model: "unsupported/extraction-model")
        }.to raise_error(ActiveRecord::RecordInvalid, /extraction model/i)
      end
    end

    describe "widened classification_model validation" do
      it "allows setting classification_model to a supported decision model" do
        expect {
          setting.update!(classification_model: "ScaleDown Classify Latest")
        }.not_to raise_error
        expect(setting.reload.classification_model).to eq("ScaleDown Classify Latest")
      end
    end

    describe "single-pass offered_decision_models_list resolution" do
      it "does not invoke OpenRouterModelsService.call and queries decision_models at most once when catalog is nil" do
        setting # ensure singleton is loaded before expectation
        expect(Llm::OpenRouterModelsService).to receive(:decision_models).and_return([]).once
        expect(Llm::OpenRouterModelsService).not_to receive(:call)

        list = setting.offered_decision_models_list(decision_catalog_models: nil)
        expect(list).to include("ScaleDown Classify Latest", "Jev Latest")
      end

      it "uses preloaded decision_catalog_models without querying decision_models" do
        # @type var preloaded: Array[Llm::OpenRouterModelsService::decision_model] # lat:ignore
        preloaded = [{id: "preloaded/decision-model", label: "Preloaded Decision", supports_reasoning: false, mode: :decision}]
        setting.update_column(:offered_models, setting.offered_models_list + ["preloaded/decision-model"])

        expect(Llm::OpenRouterModelsService).not_to receive(:decision_models)
        expect(Llm::OpenRouterModelsService).not_to receive(:call)

        list = setting.offered_decision_models_list(decision_catalog_models: preloaded)
        expect(list).to include("preloaded/decision-model")
      end
    end

    describe "offered_extraction_models_list resolution" do
      it "combines SUPPORTED_EXTRACTION_MODELS with offered_models_list" do
        list = setting.offered_extraction_models_list
        expect(list).to include("ScaleDown Extract Latest")
        expect(list).to include(*setting.offered_models_list)
      end
    end

    describe "class helpers .offered_decision_models and .offered_extraction_models" do
      it "returns offered decision and extraction models lists" do
        expect(described_class.offered_decision_models).to include("ScaleDown Classify Latest")
        expect(described_class.offered_extraction_models).to include("ScaleDown Extract Latest")
      end
    end

    describe ".offered_model_labels" do
      it "merges labels for decision and extraction models alongside catalog entries" do
        # @type var decision_catalog: Array[Llm::OpenRouterModelsService::decision_model] # lat:ignore
        decision_catalog = [
          {id: "custom/decision-label", label: "Custom Decision Label", supports_reasoning: false, mode: :decision}
        ]
        labels = described_class.offered_model_labels(decision_catalog_models: decision_catalog)

        expect(labels["ScaleDown Classify Latest"]).to eq("ScaleDown Classify Latest")
        expect(labels["ScaleDown Extract Latest"]).to eq("ScaleDown Extract Latest")
        expect(labels["custom/decision-label"]).to eq("Custom Decision Label")
      end

      it "queries decision_models at most once when decision_catalog_models is nil" do
        decision_catalog = [
          {id: "custom/decision-label", label: "Custom Decision Label", supports_reasoning: false, mode: :decision}
        ]
        expect(Llm::OpenRouterModelsService).to receive(:decision_models).and_return(decision_catalog).once
        labels = described_class.offered_model_labels(decision_catalog_models: nil)
        expect(labels["custom/decision-label"]).to eq("Custom Decision Label")
      end

      it "is resilient to exceptions from Llm::OpenRouterModelsService.decision_models" do
        allow(Llm::OpenRouterModelsService).to receive(:decision_models).and_raise(StandardError.new("API failure"))
        expect {
          labels = described_class.offered_model_labels(decision_catalog_models: nil)
          expect(labels["ScaleDown Classify Latest"]).to eq("ScaleDown Classify Latest")
        }.not_to raise_error
      end
    end

    describe "active model protection in remove_offered_model!" do
      it "refuses to remove an active decision_model" do
        setting.update_column(:offered_models, setting.offered_models_list + ["ScaleDown Classify Latest"])
        setting.update!(decision_model: "ScaleDown Classify Latest")

        expect {
          setting.remove_offered_model!("ScaleDown Classify Latest")
        }.to raise_error(ActiveRecord::RecordInvalid, /cannot remove a model that is currently active/i)
      end

      it "refuses to remove an active extraction_model" do
        setting.update_column(:offered_models, setting.offered_models_list + ["ScaleDown Extract Latest"])
        setting.update!(extraction_model: "ScaleDown Extract Latest")

        expect {
          setting.remove_offered_model!("ScaleDown Extract Latest")
        }.to raise_error(ActiveRecord::RecordInvalid, /cannot remove a model that is currently active/i)
      end
    end

    describe "stored_model? with specialized models" do
      it "returns true on class and instance for stored decision_model and extraction_model" do
        setting.update!(
          decision_model: "ScaleDown Classify Latest",
          extraction_model: "ScaleDown Extract Latest"
        )

        expect(setting.stored_model?("ScaleDown Classify Latest")).to be(true)
        expect(setting.stored_model?("ScaleDown Extract Latest")).to be(true)
        expect(described_class.stored_model?("ScaleDown Classify Latest")).to be(true)
        expect(described_class.stored_model?("ScaleDown Extract Latest")).to be(true)
      end
    end

    describe "add_offered_model! with specialized models" do
      it "accepts supported decision and extraction models without polluting offered_models_list" do
        setting.add_offered_model!("ScaleDown Classify Latest")
        expect(setting.reload.offered_decision_models_list).to include("ScaleDown Classify Latest")
        expect(setting.offered_models_list).not_to include("ScaleDown Classify Latest")
        expect(setting.offered_extraction_models_list).not_to include("ScaleDown Classify Latest")

        setting.add_offered_model!("ScaleDown Extract Latest")
        expect(setting.reload.offered_extraction_models_list).to include("ScaleDown Extract Latest")
        expect(setting.offered_models_list).not_to include("ScaleDown Extract Latest")
      end

      it "accepts dynamic decision models discovered via lookup_decision_model" do
        custom_model = {id: "custom/dynamic-decision", label: "Dynamic Decision", supports_reasoning: false, mode: :decision}
        allow(Llm::OpenRouterModelsService).to receive(:decision_models).and_return([custom_model])
        allow(Llm::OpenRouterModelsService).to receive(:lookup)
          .with("custom/dynamic-decision")
          .and_return(nil)

        setting.add_offered_model!("custom/dynamic-decision")
        expect(setting.reload.offered_decision_models_list).to include("custom/dynamic-decision")
        expect(setting.offered_models_list).not_to include("custom/dynamic-decision")
        expect(setting.offered_extraction_models_list).not_to include("custom/dynamic-decision")
      end

      it "preserves dynamic decision models when subsequently adding other models" do
        custom_model = {id: "~typesafe/jev-v2", label: "Jev v2", supports_reasoning: false, mode: :decision}
        allow(Llm::OpenRouterModelsService).to receive(:decision_models).and_return([custom_model])
        allow(Llm::OpenRouterModelsService).to receive(:lookup).and_call_original
        allow(Llm::OpenRouterModelsService).to receive(:lookup)
          .with("~typesafe/jev-v2")
          .and_return(nil)

        setting.add_offered_model!("~typesafe/jev-v2")
        expect(setting.reload.offered_decision_models_list).to include("~typesafe/jev-v2")

        setting.add_offered_model!("Sonnet Latest")
        reloaded = setting.reload
        expect(reloaded.offered_decision_models_list).to include("~typesafe/jev-v2")
        expect(reloaded.offered_models_list).to include("Sonnet Latest")
        expect(reloaded.offered_models_list).not_to include("~typesafe/jev-v2")
      end
    end

    # @lat: [[steep-typed-spec-helpers#let and def inside a describe block#Accepting the gap with steep:ignore instead of moving the helper out]]
    # steep:ignore:start
    describe "adversarial edge cases and stress areas" do
      describe "Stress Area 1: Single-pass iteration performance" do
        let(:dynamic_count) { 50 }
        let(:dynamic_models) do
          (1..dynamic_count).map do |i|
            {
              id: "dynamic/decision-model-#{i}",
              label: "Dynamic Decision #{i}",
              supports_reasoning: false,
              mode: :decision
            }.freeze
          end.freeze
        end
        let(:dynamic_model_ids) { dynamic_models.pluck(:id) }

        before do
          setting.update_column(:offered_models, AdminSetting::SUPPORTED_MODELS + dynamic_model_ids)
        end

        it "does NOT call Llm::OpenRouterModelsService.call when resolving 50 dynamic models" do
          allow(Llm::OpenRouterModelsService).to receive(:decision_models).and_return(dynamic_models)
          expect(Llm::OpenRouterModelsService).not_to receive(:call)

          list = setting.offered_decision_models_list
          expect(list).to include(*dynamic_model_ids)
          expect(list).to include(*AdminSetting::SUPPORTED_DECISION_MODELS)
        end

        it "queries Llm::OpenRouterModelsService.decision_models at most once when decision_catalog_models is nil" do
          expect(Llm::OpenRouterModelsService).to receive(:decision_models).and_return(dynamic_models).once

          list = setting.offered_decision_models_list(decision_catalog_models: nil)
          expect(list.size).to eq(AdminSetting::SUPPORTED_DECISION_MODELS.size + dynamic_count)
        end

        it "does NOT query Llm::OpenRouterModelsService.decision_models when decision_catalog_models is passed" do
          expect(Llm::OpenRouterModelsService).not_to receive(:decision_models)
          expect(Llm::OpenRouterModelsService).not_to receive(:call)

          list = setting.offered_decision_models_list(decision_catalog_models: dynamic_models)
          expect(list).to include(*dynamic_model_ids)
        end

        it "makes zero SQL queries during #offered_decision_models_list execution on a loaded record" do
          allow(Llm::OpenRouterModelsService).to receive(:decision_models).and_return(dynamic_models)

          setting.offered_models_list

          query_count = 0
          counter = lambda do |_name, _start, _finish, _id, payload|
            query_count += 1 unless %w[CACHE SCHEMA].include?(payload[:name])
          end

          ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
            setting.offered_decision_models_list
          end

          expect(query_count).to eq(0)
        end

        it "demonstrates linear O(N) performance and executes 100 calls in under 200ms" do
          allow(Llm::OpenRouterModelsService).to receive(:decision_models).and_return(dynamic_models)

          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          100.times do
            setting.offered_decision_models_list
          end
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

          expect(elapsed).to be < 0.20
        end
      end

      describe "Stress Area 2: Validation enforcement for specialized models" do
        describe "decision_model validations" do
          it "rejects nil value" do
            setting.decision_model = nil
            expect(setting.valid?).to be false
            expect(setting.errors[:decision_model]).to include(/can't be blank/i)
          end

          it "rejects empty string" do
            setting.decision_model = ""
            expect(setting.valid?).to be false
            expect(setting.errors[:decision_model]).to be_present
          end

          it "rejects whitespace-only string" do
            setting.decision_model = "   \t\n  "
            expect(setting.valid?).to be false
            expect(setting.errors[:decision_model]).to be_present
          end

          it "rejects arbitrary unoffered model strings" do
            setting.decision_model = "random/hostile-model:v1"
            expect(setting.valid?).to be false
            expect(setting.errors[:decision_model]).to include(/is not included in the list/i)
          end

          it "rejects chat-only models that are offered for summarization but not for decisions" do
            setting.decision_model = "claude-opus-5-5"
            expect(setting.valid?).to be false
            expect(setting.errors[:decision_model]).to include(/is not included in the list/i)
          end

          it "rejects unnormalized whitespace in decision model names" do
            setting.decision_model = " ScaleDown Classify Latest "
            expect(setting.valid?).to be false
            expect(setting.errors[:decision_model]).to include(/is not included in the list/i)
          end

          it "accepts all models defined in SUPPORTED_DECISION_MODELS" do
            AdminSetting::SUPPORTED_DECISION_MODELS.each do |model|
              setting.decision_model = model
              expect(setting.valid?).to be true
            end
          end

          it "accepts dynamic decision models when registered in offered_models" do
            dynamic_model = {id: "dyn/dec-1", label: "Dyn Dec 1", supports_reasoning: false, mode: :decision}
            allow(Llm::OpenRouterModelsService).to receive(:decision_models).and_return([dynamic_model])
            setting.update_column(:offered_models, setting.offered_models_list + ["dyn/dec-1"])

            setting.decision_model = "dyn/dec-1"
            expect(setting.valid?).to be true
          end
        end

        describe "extraction_model validations" do
          it "rejects nil value" do
            setting.extraction_model = nil
            expect(setting.valid?).to be false
            expect(setting.errors[:extraction_model]).to include(/can't be blank/i)
          end

          it "rejects empty string" do
            setting.extraction_model = ""
            expect(setting.valid?).to be false
            expect(setting.errors[:extraction_model]).to be_present
          end

          it "rejects whitespace-only string" do
            setting.extraction_model = "   "
            expect(setting.valid?).to be false
            expect(setting.errors[:extraction_model]).to be_present
          end

          it "rejects arbitrary unoffered model strings" do
            setting.extraction_model = "unoffered/extract-v9"
            expect(setting.valid?).to be false
            expect(setting.errors[:extraction_model]).to include(/is not included in the list/i)
          end

          it "accepts ScaleDown Extract Latest" do
            setting.extraction_model = "ScaleDown Extract Latest"
            expect(setting.valid?).to be true
          end

          it "accepts offered chat models for extraction" do
            setting.extraction_model = "Sonnet Latest"
            expect(setting.valid?).to be true
          end
        end

        describe "conditional validation on unchanged columns" do
          it "permits saving when a legacy retired decision_model is present if decision_model is not changed" do
            setting.update_column(:decision_model, "retired/decision-model-old")

            setting.extraction_model = "ScaleDown Extract Latest"
            expect(setting.valid?).to be true
            expect { setting.save! }.not_to raise_error
            expect(setting.reload.decision_model).to eq("retired/decision-model-old")
          end

          it "permits saving when a legacy retired extraction_model is present if extraction_model is not changed" do
            setting.update_column(:extraction_model, "retired/extraction-model-old")

            setting.decision_model = "ScaleDown Classify Latest"
            expect(setting.valid?).to be true
            expect { setting.save! }.not_to raise_error
            expect(setting.reload.extraction_model).to eq("retired/extraction-model-old")
          end
        end

        describe "widened classification_model validation" do
          it "accepts specialized decision models for classification" do
            setting.classification_model = "ScaleDown Classify Latest"
            expect(setting.valid?).to be true

            setting.classification_model = "Jev Latest"
            expect(setting.valid?).to be true
          end

          it "accepts general chat models for classification" do
            setting.classification_model = "claude-haiku-5-5"
            expect(setting.valid?).to be true
          end

          it "rejects unknown unoffered models for classification" do
            setting.classification_model = "hostile/unoffered"
            expect(setting.valid?).to be false
            expect(setting.errors[:classification_model]).to include(/is not included in the list/i)
          end
        end
      end

      describe "Stress Area 3: Removal protection with specialized models" do
        it "strictly rejects removal of a model currently configured as decision_model" do
          setting.update_column(:offered_models, setting.offered_models_list + ["ScaleDown Classify Latest"])
          setting.update!(decision_model: "ScaleDown Classify Latest")

          expect {
            setting.remove_offered_model!("ScaleDown Classify Latest")
          }.to raise_error(ActiveRecord::RecordInvalid) do |err|
            expect(err.record.errors[:offered_models]).to include(/cannot remove a model that is currently active/i)
          end
        end

        it "strictly rejects removal of a model currently configured as extraction_model" do
          setting.update_column(:offered_models, setting.offered_models_list + ["ScaleDown Extract Latest"])
          setting.update!(extraction_model: "ScaleDown Extract Latest")

          expect {
            setting.remove_offered_model!("ScaleDown Extract Latest")
          }.to raise_error(ActiveRecord::RecordInvalid) do |err|
            expect(err.record.errors[:offered_models]).to include(/cannot remove a model that is currently active/i)
          end
        end

        it "normalizes whitespace and symbols when evaluating removal protection" do
          setting.update_column(:offered_models, setting.offered_models_list + ["ScaleDown Classify Latest"])
          setting.update!(decision_model: "ScaleDown Classify Latest")

          expect {
            setting.remove_offered_model!("   ScaleDown Classify Latest   ")
          }.to raise_error(ActiveRecord::RecordInvalid, /cannot remove a model that is currently active/i)

          expect {
            setting.remove_offered_model!(:"ScaleDown Classify Latest")
          }.to raise_error(ActiveRecord::RecordInvalid, /cannot remove a model that is currently active/i)
        end

        it "rejects removal of an active dynamic decision model" do
          dynamic_model = {id: "openrouter/dec-test", label: "Dec Test", supports_reasoning: false, mode: :decision}
          allow(Llm::OpenRouterModelsService).to receive(:decision_models).and_return([dynamic_model])

          setting.update_column(:offered_models, setting.offered_models_list + ["openrouter/dec-test"])
          setting.update!(decision_model: "openrouter/dec-test")

          expect {
            setting.remove_offered_model!("openrouter/dec-test")
          }.to raise_error(ActiveRecord::RecordInvalid, /cannot remove a model that is currently active/i)
        end

        it "allows removal of a non-active model from offered_models" do
          candidate = "candidate/to-remove"
          setting.update_column(:offered_models, setting.offered_models_list + [candidate])
          expect(setting.offered_models_list).to include(candidate)

          expect {
            setting.remove_offered_model!(candidate)
          }.not_to raise_error

          expect(setting.reload.offered_models_list).not_to include(candidate)
        end
      end

      describe "Stress Area 4: Active setting stored model lookup" do
        before do
          setting.update!(
            summarization_model: "claude-haiku-5-5",
            classification_model: "claude-sonnet-5-5",
            decision_model: "ScaleDown Classify Latest",
            extraction_model: "ScaleDown Extract Latest"
          )
        end

        it "recognizes active decision and extraction models via string, whitespace-padded string, and symbol" do
          expect(setting.stored_model?("ScaleDown Classify Latest")).to be true
          expect(setting.stored_model?("  ScaleDown Classify Latest \t ")).to be true
          expect(setting.stored_model?(:"ScaleDown Classify Latest")).to be true

          expect(setting.stored_model?("ScaleDown Extract Latest")).to be true
          expect(setting.stored_model?("  ScaleDown Extract Latest \n ")).to be true
          expect(setting.stored_model?(:"ScaleDown Extract Latest")).to be true

          expect(described_class.stored_model?("ScaleDown Classify Latest")).to be true
          expect(described_class.stored_model?("  ScaleDown Classify Latest \t ")).to be true
          expect(described_class.stored_model?(:"ScaleDown Classify Latest")).to be true

          expect(described_class.stored_model?("ScaleDown Extract Latest")).to be true
          expect(described_class.stored_model?("  ScaleDown Extract Latest \n ")).to be true
          expect(described_class.stored_model?(:"ScaleDown Extract Latest")).to be true
        end

        it "returns false for nil, blank, numbers, and unconfigured models" do
          [nil, "", "   ", "\t\n", "nonexistent/random-model", 12345, :unknown_model].each do |target|
            expect(setting.stored_model?(target)).to be false
            expect(described_class.stored_model?(target)).to be false
          end
        end

        it "is resilient to database errors in AdminSetting.stored_model?" do
          allow(described_class).to receive(:offered_models).and_raise(ActiveRecord::ConnectionNotEstablished.new("Disconnected"))
          expect(described_class.stored_model?("ScaleDown Classify Latest")).to be false

          allow(described_class).to receive(:offered_models).and_raise(ActiveRecord::StatementInvalid.new("SQL error"))
          expect(described_class.stored_model?("ScaleDown Classify Latest")).to be false
        end
      end

      describe "Stress Area 5: Migration safety check" do
        let(:migration_file) do
          Rails.root.join("db", "migrate", "20261018000003_add_decision_and_extraction_models_to_admin_settings.rb")
        end

        it "exists and is readable" do
          expect(File.exist?(migration_file)).to be true
        end

        it "contains zero references to the AdminSetting model class" do
          content = File.read(migration_file)
          expect(content).not_to match(/\bAdminSetting\b/)
        end

        it "contains zero references to model constants" do
          content = File.read(migration_file)
          expect(content).not_to match(/SUPPORTED_/)
          expect(content).not_to match(/MODELS/)
        end

        it "uses pure ActiveRecord DDL add_column statements with explicit defaults" do
          content = File.read(migration_file)
          expect(content).to include('add_column :admin_settings, :decision_model, :string, default: "ScaleDown Classify Latest", null: false')
          expect(content).to include('add_column :admin_settings, :extraction_model, :string, default: "ScaleDown Extract Latest", null: false')
        end
      end
    end
    # steep:ignore:end
  end
end
