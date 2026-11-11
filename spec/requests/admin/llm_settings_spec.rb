# frozen_string_literal: true

require "rails_helper"

# @lat: [[admin-llm-settings-controller-design#The admin-namespace convention, and the mass-assignment guard]]
RSpec.describe "Admin::LlmSettings", type: :request do
  include_context "SessionDouble"

  include_examples "requires sway admin",
    verb: :get,
    path: "/admin/llm_settings"

  include_examples "requires sway admin",
    verb: :patch,
    path: "/admin/llm_settings",
    params: {admin_setting: {summarization_model: "claude-sonnet-5-5"}}

  include_examples "requires sway admin",
    verb: :patch,
    path: "/admin/llm_settings",
    params: {admin_setting: {summary_batch_enabled: true}}

  include_examples "requires sway admin",
    verb: :post,
    path: "/admin/llm_settings/refresh_models"

  include_examples "requires sway admin",
    verb: :post,
    path: "/admin/llm_settings/add_model",
    params: {model_id: "meta-llama/llama-3-70b-instruct"}

  include_examples "requires sway admin",
    verb: :delete,
    path: "/admin/llm_settings/remove_model",
    params: {model_id: "Deepseek Flash Latest"}

  # session[:inertia_errors] travels through the session store, which hands its keys
  # back as Strings on some paths and Symbols on others. This helper checks both, so a
  # test about which field carries an error cannot pass by accident simply because it
  # looked up the wrong kind of key.
  def admin_setting_errors_from_session
    inertia_errors = session[:inertia_errors] || {}
    inertia_errors[:admin_setting] || inertia_errors["admin_setting"] || {}
  end

  context "as a sway admin" do
    let(:admin) { create(:user, :sway_admin) }

    before { session_hash[:user_id] = admin.id }

    describe "GET /admin/llm_settings" do
      it "renders the admin/LlmSettings Inertia page with specialized model props" do
        get "/admin/llm_settings"

        expect(response).to have_http_status(:ok)
        expect(inertia).to be_inertia_response
        expect(inertia).to render_component("admin/LlmSettings")

        supported = inertia.props[:supported_models]
        expect(supported).to be_an(Array)
        expect(supported.length).to eq(12)
        expect(supported.pluck(:id)).to match_array(
          AdminSetting::SUPPORTED_MODELS
        )
        expect(supported.pluck(:label)).to all(be_present)
        expect(supported.pluck(:selectable)).to all(be(true))

        available = inertia.props[:available_openrouter_models]
        expect(available).to be_an(Array)
        expect(available.pluck(:id)).not_to include(*AdminSetting.singleton.offered_models_list)

        expect(inertia.props[:current_summarization_model]).to eq("claude-haiku-5-5")
        expect(inertia.props[:current_decision_model]).to eq("ScaleDown Classify Latest")
        expect(inertia.props[:current_extraction_model]).to eq("ScaleDown Extract Latest")
        expect(inertia.props[:current_summarization_reasoning_effort]).to be_nil
        expect(inertia.props[:current_classification_reasoning_effort]).to be_nil
        expect(inertia.props[:updated_by]).to be_nil
        expect(inertia.props[:updated_at]).to be_a(String)
        expect { Time.iso8601(inertia.props[:updated_at]) }.not_to raise_error

        decision_models = inertia.props[:supported_decision_models]
        expect(decision_models).to be_an(Array)
        expect(decision_models.length).to eq(4)
        expect(decision_models.pluck(:id)).to match_array(AdminSetting::SUPPORTED_DECISION_MODELS)
        expect(decision_models.pluck(:selectable)).to all(be(true))
        expect(decision_models.pluck(:supports_reasoning)).to all(be(false))

        extraction_models = inertia.props[:supported_extraction_models]
        expect(extraction_models).to be_an(Array)
        expect(extraction_models.pluck(:id)).to include("ScaleDown Extract Latest")
        expect(extraction_models.pluck(:selectable)).to all(be(true))

        argon = supported.find { |m| m[:id] == "Gemini Argon Latest" }
        expect(argon[:supports_reasoning]).to be(true)

        haiku = supported.find { |m| m[:id] == "claude-haiku-5-5" }
        expect(haiku[:supports_reasoning]).to be(false)
      end

      it "queries OpenRouterModelsService.call and .decision_models at most once per request" do
        AdminSetting.singleton
        expect(Llm::OpenRouterModelsService).to receive(:call).at_most(:once).and_call_original
        expect(Llm::OpenRouterModelsService).to receive(:decision_models).at_most(:once).and_call_original

        get "/admin/llm_settings"

        expect(response).to have_http_status(:ok)
      end

      it "includes unoffered dynamic decision models from OpenRouterModelsService.decision_models in available_openrouter_models" do
        decision_catalog_mock = [
          {id: "~typesafe/jev-v2", label: "Jev v2", supports_reasoning: false, mode: :decision}
        ]
        allow(Llm::OpenRouterModelsService).to receive(:decision_models).and_return(decision_catalog_mock)

        get "/admin/llm_settings"

        expect(response).to have_http_status(:ok)
        available = inertia.props[:available_openrouter_models]
        expect(available.pluck(:id)).to include("~typesafe/jev-v2")
        jev_entry = available.find { |m| m[:id] == "~typesafe/jev-v2" }
        expect(jev_entry[:label]).to eq("Jev v2")
        expect(jev_entry[:supports_reasoning]).to be(false)
      end

      it "includes unoffered OpenRouter catalog models and removed baseline models in available_openrouter_models" do
        catalog_mock = [
          {id: "openai/gpt-4o", label: "GPT-4o", supports_reasoning: false},
          {id: "meta-llama/llama-3-70b-instruct", label: "Llama 3 70B", supports_reasoning: false}
        ]
        allow(Llm::OpenRouterModelsService).to receive(:call).and_return(catalog_mock)
        AdminSetting.singleton.update!(
          offered_models: AdminSetting::SUPPORTED_MODELS - ["Deepseek Flash Latest"]
        )

        get "/admin/llm_settings"

        expect(response).to have_http_status(:ok)
        available = inertia.props[:available_openrouter_models]
        available_ids = available.pluck(:id)
        expect(available_ids).to include("Deepseek Flash Latest", "openai/gpt-4o", "meta-llama/llama-3-70b-instruct")

        removed_entry = available.find { |m| m[:id] == "Deepseek Flash Latest" }
        expect(removed_entry).to be_present
        expect(removed_entry[:label]).to eq("Deepseek Flash Latest")
      end

      context "with multiple dynamic OpenRouter models offered" do
        include_context "with in-memory Rails.cache"

        before do
          catalog = [
            {id: "openai/gpt-4o", label: "OpenAI: GPT-4o", supports_reasoning: false},
            {id: "mistralai/mistral-large", label: "Mistral Large", supports_reasoning: false},
            {id: "qwen/qwen-2.5-72b-instruct", label: "Qwen 2.5 72B", supports_reasoning: true}
          ]
          Rails.cache.write(Llm::OpenRouterModelsService::CACHE_KEY, catalog)
          AdminSetting.singleton.update!(
            offered_models: ["claude-haiku-5-5", "openai/gpt-4o", "mistralai/mistral-large", "qwen/qwen-2.5-72b-instruct"]
          )
        end

        it "queries the OpenRouter catalog at most once across model options and labels" do
          expect(Llm::OpenRouterModelsService).to receive(:call).at_most(:once).and_call_original

          get "/admin/llm_settings"

          expect(response).to have_http_status(:ok)
        end
      end
    end

    describe "#model_options query efficiency" do
      let(:controller) { Admin::LlmSettingsController.new }
      let(:setting) { AdminSetting.singleton }

      it "uses setting.offered_models_list from the passed record and does not invoke AdminSetting.offered_models" do
        expect(setting).to receive(:offered_models_list).at_least(:once).and_call_original
        expect(AdminSetting).not_to receive(:offered_models)

        options = controller.send(:model_options, setting, catalog_models: [], labels: {})
        expect(options).to be_an(Array)
      end
    end

    # @lat: [[explanation/llm-summaries#Settings live in the database#A stored model that is no longer offered]]
    describe "GET /admin/llm_settings — a stored model that is no longer offered" do
      # @lat: [[admin-setting-model-list#Why the retired-model tests write the column directly]]
      it "sends it as an unselectable option rather than leaving it out" do
        AdminSetting.singleton.update_column(:summarization_model, "claude-sonnet-4-6")

        get "/admin/llm_settings"

        supported = inertia.props[:supported_models]
        retired = supported.find { |model| model[:id] == "claude-sonnet-4-6" }

        expect(retired).to be_present
        expect(retired[:selectable]).to be(false)
        expect(retired[:label]).to include("no longer offered")
        expect(supported.last[:id]).to eq("claude-sonnet-4-6")
        expect(supported.reject { |model| model[:id] == "claude-sonnet-4-6" }.pluck(:selectable)).to all(be(true))
      end

      # The screen is not just readable in that state — it is usable. An admin
      # can still change the other model, which is the thing an unconditional
      # allowlist check made impossible.
      it "still lets the other model be saved while that value is stored" do
        AdminSetting.singleton.update_column(:summarization_model, "claude-sonnet-4-6")

        patch "/admin/llm_settings",
          params: {admin_setting: {classification_model: "claude-sonnet-5-5"}}

        expect(AdminSetting.singleton.reload.classification_model).to eq("claude-sonnet-5-5")
        expect(AdminSetting.singleton.summarization_model).to eq("claude-sonnet-4-6")
      end
    end

    # If the admin who made the change has no full_name, the page must not fall back to
    # showing their phone number. A phone number identifies a person, which is why Rails
    # is already told to keep it out of the logs. A neutral label is sent instead.
    describe "GET /admin/llm_settings — provenance never exposes User#phone" do
      it "uses a neutral label (not phone) when the updater has no full_name" do
        admin.update!(full_name: nil)
        AdminSetting.singleton.update!(
          summarization_model: "claude-sonnet-5-5",
          updated_by_id: admin.id
        )

        get "/admin/llm_settings"

        expect(response).to have_http_status(:ok)
        updated_by = inertia.props[:updated_by]
        expect(updated_by).to be_a(Hash)
        expect(updated_by[:name]).not_to eq(admin.phone)
        expect(updated_by[:name]).not_to include(admin.phone.to_s)
        expect(updated_by[:name]).to eq("Admin (no name set)")
      end
    end

    describe "PATCH /admin/llm_settings (happy path — nested admin_setting param shape)" do
      it "updates the singleton, captures provenance, redirects with flash[:notice]" do
        patch "/admin/llm_settings",
          params: {admin_setting: {summarization_model: "claude-sonnet-5-5"}}

        expect(response).to redirect_to("/admin/llm_settings")
        expect(flash[:notice]).to eq("Model updated.")

        AdminSetting.singleton.reload
        expect(AdminSetting.singleton.summarization_model).to eq("claude-sonnet-5-5")
        expect(AdminSetting.singleton.updated_by_id).to eq(admin.id)
      end

      # After saving, the browser is sent back to the page, so pressing reload cannot
      # submit the form twice. The admin has to see the new value straight away, with no
      # manual refresh. This follows the redirect and checks the props really do carry
      # the updated setting, so a later change that breaks that fails here.
      it "exposes the updated singleton via Inertia props after the PRG redirect" do
        patch "/admin/llm_settings",
          params: {admin_setting: {summarization_model: "claude-sonnet-5-5"}}
        follow_redirect!

        expect(inertia).to render_component("admin/LlmSettings")
        expect(inertia.props[:current_summarization_model]).to eq("claude-sonnet-5-5")
        expect(inertia.props[:updated_by]).to be_a(Hash)
        expect(inertia.props[:updated_by][:name]).to be_present
      end
    end

    describe "PATCH /admin/llm_settings (invalid model — allowlist rejects)" do
      # @lat: [[admin-llm-settings-controller-design#Mapping validation errors to fields]]
      it "redirects with Inertia errors and does not mutate the singleton" do
        # Note the value beforehand, so the test can show nothing changed.
        AdminSetting.singleton.update!(
          summarization_model: "claude-haiku-5-5",
          updated_by_id: admin.id
        )

        patch "/admin/llm_settings",
          params: {admin_setting: {summarization_model: "gpt-4"}}

        expect(response).to redirect_to("/admin/llm_settings")
        # No banner across the top: the message travels in the errors prop rather than
        # the flash alert.
        expect(flash[:alert]).to be_nil

        # session[:inertia_errors] is how the message survives the redirect; the next
        # page render folds it into the shared `errors` prop.
        inertia_errors = session[:inertia_errors] || {}
        expect(inertia_errors).to be_a(Hash)
        expect(inertia_errors[:admin_setting] || inertia_errors["admin_setting"]).to be_a(Hash)
        admin_setting_errors =
          inertia_errors[:admin_setting] || inertia_errors["admin_setting"]
        expect(
          admin_setting_errors[:summarization_model] ||
            admin_setting_errors["summarization_model"]
        ).to eq("Model not recognized. Choose from the list.")

        # The full round trip: following the redirect renders the page again, and the
        # shared `errors` prop still holds the same message.
        follow_redirect!
        expect(inertia).to be_inertia_response
        errors_prop = inertia.props[:errors] || {}
        expect(errors_prop[:admin_setting] || errors_prop["admin_setting"]).to be_a(Hash)

        AdminSetting.singleton.reload
        expect(AdminSetting.singleton.summarization_model).to eq("claude-haiku-5-5")
      end
    end

    describe "PATCH /admin/llm_settings (dual-format negotiation)" do
      # Clients that ask for JSON — the mobile admin screen, curl scripts, internal
      # integrations — get a JSON body rather than a redirect and a flash message. That
      # body is deliberately small: summarization_model, updated_by_id and updated_at
      # only, not the whole record.
      it "returns JSON on success when Accept: application/json" do
        patch "/admin/llm_settings",
          params: {admin_setting: {summarization_model: "claude-sonnet-5-5"}},
          headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/json")
        body = JSON.parse(response.body)
        expect(body["summarization_model"]).to eq("claude-sonnet-5-5")
        expect(body["updated_by_id"]).to eq(admin.id)
        expect(body["updated_at"]).to be_a(String)
        # Kept small on purpose: id and created_at are not sent.
        expect(body).not_to have_key("id")
        expect(body).not_to have_key("created_at")
      end

      it "updates summarization_reasoning_effort and classification_reasoning_effort" do
        patch "/admin/llm_settings",
          params: {
            admin_setting: {
              summarization_model: "Gemini Argon Latest",
              classification_model: "Opus Latest",
              summarization_reasoning_effort: "high",
              classification_reasoning_effort: "low"
            }
          }

        expect(response).to redirect_to("/admin/llm_settings")
        expect(flash[:notice]).to eq("Model updated.")

        setting = AdminSetting.singleton.reload
        expect(setting.summarization_model).to eq("Gemini Argon Latest")
        expect(setting.classification_model).to eq("Opus Latest")
        expect(setting.summarization_reasoning_effort).to eq("high")
        expect(setting.classification_reasoning_effort).to eq("low")
        expect(setting.updated_by_id).to eq(admin.id)
      end

      it "includes reasoning efforts in dual-format JSON response" do
        AdminSetting.singleton.update!(
          summarization_model: "Gemini Argon Latest",
          classification_model: "Opus Latest",
          updated_by_id: admin.id
        )

        patch "/admin/llm_settings",
          params: {
            admin_setting: {
              summarization_reasoning_effort: "medium",
              classification_reasoning_effort: "high"
            }
          },
          headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["summarization_reasoning_effort"]).to eq("medium")
        expect(body["classification_reasoning_effort"]).to eq("high")
      end

      it "clears summarization_reasoning_effort when switching from a reasoning model to claude-haiku-5-5" do
        AdminSetting.singleton.update!(
          summarization_model: "Opus Latest",
          summarization_reasoning_effort: "high",
          updated_by_id: admin.id
        )

        patch "/admin/llm_settings",
          params: {
            admin_setting: {
              summarization_model: "claude-haiku-5-5"
            }
          }

        expect(response).to redirect_to("/admin/llm_settings")
        follow_redirect!
        expect(inertia).to render_component("admin/LlmSettings")
        expect(inertia.props[:current_summarization_model]).to eq("claude-haiku-5-5")
        expect(inertia.props[:current_summarization_reasoning_effort]).to be_nil

        setting = AdminSetting.singleton.reload
        expect(setting.summarization_model).to eq("claude-haiku-5-5")
        expect(setting.summarization_reasoning_effort).to be_nil
      end

      it "clears summarization_reasoning_effort in dual-format JSON response when switching to a non-reasoning model" do
        AdminSetting.singleton.update!(
          summarization_model: "Opus Latest",
          summarization_reasoning_effort: "high",
          updated_by_id: admin.id
        )

        patch "/admin/llm_settings",
          params: {
            admin_setting: {
              summarization_model: "claude-haiku-5-5"
            }
          },
          headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["summarization_model"]).to eq("claude-haiku-5-5")
        expect(body["summarization_reasoning_effort"]).to be_nil
      end

      it "returns 422 JSON on allowlist rejection when Accept: application/json" do
        AdminSetting.singleton.update!(
          summarization_model: "claude-haiku-5-5",
          updated_by_id: admin.id
        )

        patch "/admin/llm_settings",
          params: {admin_setting: {summarization_model: "gpt-4"}},
          headers: {"Accept" => "application/json"}

        # :unprocessable_content is Rack's current name for this status;
        # :unprocessable_entity is deprecated. Either way the number is 422.
        expect(response).to have_http_status(422)
        expect(response.media_type).to eq("application/json")
        body = JSON.parse(response.body)
        expect(body["error"]).to eq({"code" => "validation_failed", "message" => "Model not recognized."})

        AdminSetting.singleton.reload
        expect(AdminSetting.singleton.summarization_model).to eq("claude-haiku-5-5")
      end
    end

    describe "PATCH /admin/llm_settings (mass-assignment defense — T-54-02-03)" do
      # A request body that tries to set updated_by_id itself must be ignored. The
      # server fills updated_by_id in from current_user.id, outside the permitted
      # parameters.
      it "uses current_user.id for updated_by_id; ignores attacker-supplied value" do
        attacker_id = 99_999

        patch "/admin/llm_settings",
          params: {
            admin_setting: {
              summarization_model: "claude-sonnet-5-5",
              updated_by_id: attacker_id
            }
          }

        expect(response).to redirect_to("/admin/llm_settings")

        AdminSetting.singleton.reload
        expect(AdminSetting.singleton.summarization_model).to eq("claude-sonnet-5-5")
        expect(AdminSetting.singleton.updated_by_id).to eq(admin.id)
        expect(AdminSetting.singleton.updated_by_id).not_to eq(attacker_id)
      end
    end

    # The model the testimony classifier uses is a second setting, adjustable on its
    # own, stored on the same record and limited to the same list of models.
    describe "PATCH /admin/llm_settings (classification_model)" do
      it "updates classification_model on its own" do
        patch "/admin/llm_settings",
          params: {admin_setting: {classification_model: "claude-sonnet-5-5"}}

        expect(response).to redirect_to("/admin/llm_settings")
        AdminSetting.singleton.reload
        expect(AdminSetting.singleton.classification_model).to eq("claude-sonnet-5-5")
        expect(AdminSetting.singleton.updated_by_id).to eq(admin.id)
      end

      it "updates both models in one submit" do
        patch "/admin/llm_settings",
          params: {admin_setting: {summarization_model: "claude-opus-5-5", classification_model: "claude-sonnet-5-5"}}

        AdminSetting.singleton.reload
        expect(AdminSetting.singleton.summarization_model).to eq("claude-opus-5-5")
        expect(AdminSetting.singleton.classification_model).to eq("claude-sonnet-5-5")
      end

      # Sending only one of the two fields must not knock the other back to its
      # default. The web page sends both, but a JSON client does not have to.
      it "leaves classification_model alone when only summarization_model is submitted" do
        AdminSetting.singleton.update!(classification_model: "claude-sonnet-5-5")

        patch "/admin/llm_settings",
          params: {admin_setting: {summarization_model: "claude-opus-5-5"}}

        expect(AdminSetting.singleton.reload.classification_model).to eq("claude-sonnet-5-5")
      end

      it "rejects a non-allowlisted classification_model without changing the row" do
        AdminSetting.singleton.update!(classification_model: "claude-haiku-5-5")

        patch "/admin/llm_settings",
          params: {admin_setting: {classification_model: "gpt-4"}}

        expect(AdminSetting.singleton.reload.classification_model).to eq("claude-haiku-5-5")
      end

      # @lat: [[admin-llm-settings-controller-design#Why rejected_model_errors's per-column attribution has its own regression test]]
      it "prints a refused classification_model under the classification field and not the other one" do
        patch "/admin/llm_settings",
          params: {admin_setting: {classification_model: "gpt-4"}}

        errors = admin_setting_errors_from_session
        expect(errors[:classification_model] || errors["classification_model"])
          .to eq("Model not recognized. Choose from the list.")
        expect(errors.key?(:summarization_model) || errors.key?("summarization_model")).to be(false)
      end

      # @lat: [[admin-llm-settings-controller-design#Why rejected_model_errors's per-column attribution has its own regression test]]
      it "does not claim the model was unrecognized when the failure is not attributable to either field" do
        AdminSetting.singleton # bring the one real row into existence
        # A second AdminSetting is then invalid for one reason only — there may be just
        # one of these rows — while both model columns hold allowed values. That is the
        # only failure this model can produce that belongs to neither column.
        unsaveable = AdminSetting.new(
          summarization_model: AdminSetting::SUPPORTED_MODELS.first,
          classification_model: AdminSetting::SUPPORTED_MODELS.first
        )
        expect(unsaveable).not_to be_valid
        expect(unsaveable.errors.attribute_names).to eq([:base])
        allow(AdminSetting).to receive(:singleton).and_return(unsaveable)

        patch "/admin/llm_settings",
          params: {admin_setting: {summarization_model: "claude-sonnet-5-5"}}

        message = admin_setting_errors_from_session.values.first.to_s
        expect(message).to be_present
        expect(message).not_to match(/not recognized/i)
        expect(message).to include("singleton")
      end

      # The same fault in the other place it lives: the JSON path answered "Model not
      # recognized." for any validation failure at all. The same untruth on a different
      # surface, and this one is read by scripts that may act on it.
      it "does not claim the model was unrecognized in the JSON branch either" do
        AdminSetting.singleton
        unsaveable = AdminSetting.new(
          summarization_model: AdminSetting::SUPPORTED_MODELS.first,
          classification_model: AdminSetting::SUPPORTED_MODELS.first
        )
        allow(AdminSetting).to receive(:singleton).and_return(unsaveable)

        patch "/admin/llm_settings",
          params: {admin_setting: {summarization_model: "claude-sonnet-5-5"}},
          as: :json

        message = response.parsed_body.dig("error", "message").to_s
        expect(message).not_to match(/not recognized/i)
        expect(message).to include("singleton")
      end

      # The server side of the stale-write rule. The browser side is proved in
      # spec/system/admin_llm_settings_spec.rb; these tests pin the rule itself, the
      # deliberate exception included.
      describe "stale-write refusal (B2-WR-03)" do
        it "refuses a submit whose expected value no longer matches the row" do
          AdminSetting.singleton.update!(summarization_model: "claude-sonnet-5-5")

          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                summarization_model: "claude-opus-5-5",
                expected: {summarization_model: "claude-haiku-5-5"}
              }
            }

          expect(AdminSetting.singleton.reload.summarization_model).to eq("claude-sonnet-5-5")
          message = admin_setting_errors_from_session.values.first.to_s
          expect(message).to include("Someone else changed this")
          expect(message).to include("Sonnet 5.5 — balanced")
        end

        # @lat: [[admin-llm-settings-stale-write-race#Why the stale-conflict message is a refusal the admin can act on]]
        it "asks for no browser refresh, because the redirect already shows the current value" do
          AdminSetting.singleton.update!(summarization_model: "claude-sonnet-5-5")

          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                summarization_model: "claude-opus-5-5",
                expected: {summarization_model: "claude-haiku-5-5"}
              }
            }

          message = admin_setting_errors_from_session.values.first.to_s
          expect(message).not_to match(/reload|refresh/i)

          follow_redirect!
          expect(inertia.props[:current_summarization_model]).to eq("claude-sonnet-5-5")
        end

        # The script's twin of the sentence above. It carries no page wording,
        # because a JSON client has neither the page nor the button that one
        # points at.
        it "tells a JSON client which column moved and how to re-read it" do
          AdminSetting.singleton.update!(summarization_model: "claude-sonnet-5-5")

          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                summarization_model: "claude-opus-5-5",
                expected: {summarization_model: "claude-haiku-5-5"}
              }
            },
            as: :json

          message = response.parsed_body.dig("error", "message").to_s
          expect(message).to include("summarization_model")
          expect(message).to include("GET /admin/llm_settings")
          expect(message).not_to match(/reload|refresh|notice above/i)
        end

        it "applies a submit whose expected value still matches" do
          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                summarization_model: "claude-opus-5-5",
                expected: {summarization_model: "claude-haiku-5-5"}
              }
            }

          expect(AdminSetting.singleton.reload.summarization_model).to eq("claude-opus-5-5")
        end

        # Two admins changing different settings is the ordinary case, and both changes
        # have to go through. A single version number covering the whole row would have
        # rejected one of them, which is why the check is made field by field.
        it "does not refuse a field whose expected value matches just because the OTHER field moved" do
          AdminSetting.singleton.update!(classification_model: "claude-sonnet-5-5")

          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                summarization_model: "claude-opus-5-5",
                expected: {summarization_model: "claude-haiku-5-5"}
              }
            }

          AdminSetting.singleton.reload
          expect(AdminSetting.singleton.summarization_model).to eq("claude-opus-5-5")
          expect(AdminSetting.singleton.classification_model).to eq("claude-sonnet-5-5")
        end

        # A deliberate exception: a script talking JSON has no page open, so there is no
        # older view of the value for it to be out of date against. It conflicts with
        # nothing, and every existing caller keeps working.
        it "applies a submit that carries no expected block at all" do
          AdminSetting.singleton.update!(summarization_model: "claude-sonnet-5-5")

          patch "/admin/llm_settings",
            params: {admin_setting: {summarization_model: "claude-opus-5-5"}}

          expect(AdminSetting.singleton.reload.summarization_model).to eq("claude-opus-5-5")
        end

        it "answers a JSON client with 409 and a stale_write code" do
          AdminSetting.singleton.update!(summarization_model: "claude-sonnet-5-5")

          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                summarization_model: "claude-opus-5-5",
                expected: {summarization_model: "claude-haiku-5-5"}
              }
            },
            as: :json

          expect(response).to have_http_status(:conflict)
          expect(response.parsed_body.dig("error", "code")).to eq("stale_write")
          expect(AdminSetting.singleton.reload.summarization_model).to eq("claude-sonnet-5-5")
        end

        # @lat: [[admin-llm-settings-controller-design#Why apply_submitted_models locks the whole read-decide-write]]
        it "checks the expected value against the row it is about to write, not a copy read earlier" do
          # The row as an earlier read saw it, still holding the seeded value, while the
          # database has moved on underneath — exactly what a second admin's save does
          # between this request reading the row and writing it.
          stale = AdminSetting.singleton
          AdminSetting.where(id: stale.id).update_all(summarization_model: "claude-sonnet-5-5")
          allow(AdminSetting).to receive(:singleton).and_return(stale)

          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                summarization_model: "claude-opus-5-5",
                expected: {summarization_model: "claude-haiku-5-5"}
              }
            }

          expect(AdminSetting.unscoped.first.summarization_model).to eq("claude-sonnet-5-5")
        end

        it "does not report a model update for a body that submits no model at all" do
          patch "/admin/llm_settings",
            params: {admin_setting: {expected: {summarization_model: "claude-haiku-5-5"}}}

          expect(flash[:notice]).not_to eq("Model updated.")
          # The write that "changed nothing" still stamped who did it, which is how an
          # audit trail ends up recording something that never happened.
          expect(AdminSetting.singleton.reload.updated_by_id).to be_nil
        end

        it "does not report a model update when the submitted values are already stored" do
          current = AdminSetting.singleton.summarization_model

          patch "/admin/llm_settings", params: {admin_setting: {summarization_model: current}}

          expect(flash[:notice]).not_to eq("Model updated.")
          expect(AdminSetting.singleton.reload.updated_by_id).to be_nil
        end

        it "treats a reasoning effort submitted for a non-reasoning model as unchanged when already nil" do
          AdminSetting.singleton.update!(
            summarization_model: "claude-haiku-5-5",
            summarization_reasoning_effort: nil,
            updated_by_id: nil
          )

          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                summarization_reasoning_effort: "high"
              }
            }

          expect(flash[:notice]).to eq(Admin::LlmSettingsController::UNCHANGED_MESSAGE)
          expect(AdminSetting.singleton.reload.updated_by_id).to be_nil
        end

        it "does not let a stale expected block smuggle a value past the allowlist" do
          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                summarization_model: "gpt-4",
                expected: {summarization_model: "claude-haiku-5-5"}
              }
            }

          expect(AdminSetting.singleton.reload.summarization_model).to eq("claude-haiku-5-5")
          errors = admin_setting_errors_from_session
          expect(errors[:summarization_model] || errors["summarization_model"])
            .to eq("Model not recognized. Choose from the list.")
        end

        it "resolves model labels at most once across multiple stale model fields" do
          catalog = [
            {id: "openai/gpt-4o", label: "GPT-4o"},
            {id: "mistralai/mistral-large", label: "Mistral Large"}
          ]
          allow(Llm::OpenRouterModelsService).to receive(:call).and_return(catalog)
          AdminSetting.singleton.update!(
            offered_models: ["claude-haiku-5-5", "openai/gpt-4o", "mistralai/mistral-large"],
            summarization_model: "openai/gpt-4o",
            classification_model: "mistralai/mistral-large"
          )

          expect(AdminSetting).to receive(:offered_model_labels).at_most(:once).and_call_original

          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                summarization_model: "claude-haiku-5-5",
                classification_model: "claude-haiku-5-5",
                expected: {
                  summarization_model: "claude-haiku-5-5",
                  classification_model: "claude-haiku-5-5"
                }
              }
            }

          expect(response).to redirect_to("/admin/llm_settings")
          errors = admin_setting_errors_from_session
          expect(errors[:summarization_model].to_s).to include("GPT-4o")
          expect(errors[:classification_model].to_s).to include("Mistral Large")
        end

        it "does not query model labels when only non-model fields are stale" do
          AdminSetting.singleton.update!(summary_batch_enabled: true)
          expect(AdminSetting).not_to receive(:offered_model_labels)

          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                summary_batch_enabled: false,
                expected: {summary_batch_enabled: false}
              }
            }

          expect(response).to redirect_to("/admin/llm_settings")
        end

        it "detects a stale conflict on JSON requests when expected reasoning effort is nil and DB changed to high" do
          AdminSetting.singleton.update!(
            summarization_model: "Opus Latest",
            summarization_reasoning_effort: "high"
          )

          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                summarization_reasoning_effort: "low",
                expected: {summarization_reasoning_effort: nil}
              }
            },
            as: :json

          expect(response).to have_http_status(:conflict)
          body = response.parsed_body
          expect(body.dig("error", "code")).to eq("stale_write")
          expect(body.dig("error", "message")).to include("summarization_reasoning_effort is now high")
          expect(AdminSetting.singleton.reload.summarization_reasoning_effort).to eq("high")
        end
      end

      it "attributes each refusal separately when both models are refused at once" do
        patch "/admin/llm_settings",
          params: {admin_setting: {summarization_model: "gpt-4", classification_model: "gemini-pro"}}

        errors = admin_setting_errors_from_session
        expect(errors[:summarization_model] || errors["summarization_model"]).to be_present
        expect(errors[:classification_model] || errors["classification_model"]).to be_present
      end

      it "exposes both current models as Inertia props" do
        AdminSetting.singleton.update!(classification_model: "claude-sonnet-5-5")

        get "/admin/llm_settings"

        expect(inertia.props[:current_classification_model]).to eq("claude-sonnet-5-5")
        expect(inertia.props[:current_summarization_model]).to eq("claude-haiku-5-5")
      end

      it "returns both models in the JSON branch" do
        patch "/admin/llm_settings",
          params: {admin_setting: {classification_model: "claude-sonnet-5-5"}},
          as: :json

        body = response.parsed_body
        expect(body["classification_model"]).to eq("claude-sonnet-5-5")
        expect(body["summarization_model"]).to be_present
      end
    end

    # @lat: [[llm-summaries#Batch summarisation#Why the batch path is off until it is switched on]]
    describe "PATCH /admin/llm_settings (summary_batch_enabled)" do
      it "is off until an admin turns it on" do
        expect(AdminSetting.singleton.summary_batch_enabled).to be(false)

        patch "/admin/llm_settings",
          params: {admin_setting: {summary_batch_enabled: true}}

        expect(response).to redirect_to("/admin/llm_settings")
        AdminSetting.singleton.reload
        expect(AdminSetting.singleton.summary_batch_enabled).to be(true)
        expect(AdminSetting.singleton.updated_by_id).to eq(admin.id)
      end

      it "turns off again" do
        AdminSetting.singleton.update!(summary_batch_enabled: true)

        patch "/admin/llm_settings",
          params: {admin_setting: {summary_batch_enabled: false}}

        expect(AdminSetting.singleton.reload.summary_batch_enabled).to be(false)
      end

      # An HTML checkbox posts "1" / "0", never a JSON boolean.
      it "accepts the strings a checkbox posts" do
        patch "/admin/llm_settings", params: {admin_setting: {summary_batch_enabled: "1"}}
        expect(AdminSetting.singleton.reload.summary_batch_enabled).to be(true)

        patch "/admin/llm_settings", params: {admin_setting: {summary_batch_enabled: "0"}}
        expect(AdminSetting.singleton.reload.summary_batch_enabled).to be(false)
      end

      it "does not report an update, or stamp an author, when the submitted value is already stored" do
        patch "/admin/llm_settings", params: {admin_setting: {summary_batch_enabled: "0"}}

        expect(flash[:notice]).to eq(Admin::LlmSettingsController::UNCHANGED_MESSAGE)
        expect(AdminSetting.singleton.reload.updated_by_id).to be_nil
      end

      it "does not call a save that moved only this flag a model change" do
        patch "/admin/llm_settings", params: {admin_setting: {summary_batch_enabled: true}}

        expect(flash[:notice]).to eq("Settings updated.")
      end

      it "still reports a model update when a model was submitted alongside it" do
        patch "/admin/llm_settings",
          params: {admin_setting: {summarization_model: "claude-sonnet-5-5", summary_batch_enabled: true}}

        expect(flash[:notice]).to eq("Model updated.")
        AdminSetting.singleton.reload
        expect(AdminSetting.singleton.summarization_model).to eq("claude-sonnet-5-5")
        expect(AdminSetting.singleton.summary_batch_enabled).to be(true)
      end

      it "leaves the flag alone when only a model is submitted" do
        AdminSetting.singleton.update!(summary_batch_enabled: true)

        patch "/admin/llm_settings", params: {admin_setting: {summarization_model: "claude-sonnet-5-5"}}

        expect(AdminSetting.singleton.reload.summary_batch_enabled).to be(true)
      end

      it "leaves both models alone when only the flag is submitted" do
        patch "/admin/llm_settings", params: {admin_setting: {summary_batch_enabled: true}}

        AdminSetting.singleton.reload
        expect(AdminSetting.singleton.summarization_model).to eq("claude-haiku-5-5")
        expect(AdminSetting.singleton.classification_model).to eq("claude-haiku-5-5")
      end

      it "exposes the stored value as its own Inertia prop" do
        AdminSetting.singleton.update!(summary_batch_enabled: true)

        get "/admin/llm_settings"

        expect(inertia.props[:current_summary_batch_enabled]).to be(true)
      end

      it "defaults that prop to false" do
        get "/admin/llm_settings"

        expect(inertia.props[:current_summary_batch_enabled]).to be(false)
      end

      it "returns the flag in the JSON branch" do
        patch "/admin/llm_settings",
          params: {admin_setting: {summary_batch_enabled: true}},
          as: :json

        expect(response.parsed_body["summary_batch_enabled"]).to be(true)
      end

      # A boolean cannot be off the model allowlist, so its refusal must not
      # borrow the allowlist's sentence.
      it "does not call a refused flag an unrecognized model" do
        setting = AdminSetting.singleton
        invalid = AdminSetting.new
        invalid.errors.add(:summary_batch_enabled, "cannot be turned on right now")
        allow(setting).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(invalid))
        allow(AdminSetting).to receive(:singleton).and_return(setting)

        patch "/admin/llm_settings", params: {admin_setting: {summary_batch_enabled: true}}

        errors = admin_setting_errors_from_session
        message = (errors[:summary_batch_enabled] || errors["summary_batch_enabled"]).to_s
        expect(message).to include("cannot be turned on right now")
        expect(message).not_to match(/not recognized/i)
        expect(errors.key?(:summarization_model) || errors.key?("summarization_model")).to be(false)
      end

      it "does not call a refused flag an unrecognized model in the JSON branch either" do
        setting = AdminSetting.singleton
        invalid = AdminSetting.new
        invalid.errors.add(:summary_batch_enabled, "cannot be turned on right now")
        allow(setting).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(invalid))
        allow(AdminSetting).to receive(:singleton).and_return(setting)

        patch "/admin/llm_settings",
          params: {admin_setting: {summary_batch_enabled: true}},
          as: :json

        message = response.parsed_body.dig("error", "message").to_s
        expect(message).to include("cannot be turned on right now")
        expect(message).not_to match(/not recognized/i)
      end

      describe "stale-write refusal" do
        it "refuses a submit whose expected value no longer matches the row" do
          AdminSetting.singleton.update!(summary_batch_enabled: true)

          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                summary_batch_enabled: false,
                expected: {summary_batch_enabled: false}
              }
            }

          expect(AdminSetting.singleton.reload.summary_batch_enabled).to be(true)
          errors = admin_setting_errors_from_session
          message = (errors[:summary_batch_enabled] || errors["summary_batch_enabled"]).to_s
          expect(message).to include("Someone else changed this to on")
          expect(message).not_to match(/reload|refresh/i)
        end

        it "applies a submit whose expected value still matches" do
          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                summary_batch_enabled: true,
                expected: {summary_batch_enabled: false}
              }
            }

          expect(AdminSetting.singleton.reload.summary_batch_enabled).to be(true)
        end

        it "reads an expected value sent as the string a checkbox posts" do
          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                summary_batch_enabled: "1",
                expected: {summary_batch_enabled: "0"}
              }
            }

          expect(AdminSetting.singleton.reload.summary_batch_enabled).to be(true)
        end

        it "does not refuse the flag just because a model moved" do
          AdminSetting.singleton.update!(summarization_model: "claude-sonnet-5-5")

          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                summary_batch_enabled: true,
                expected: {summary_batch_enabled: false}
              }
            }

          AdminSetting.singleton.reload
          expect(AdminSetting.singleton.summary_batch_enabled).to be(true)
          expect(AdminSetting.singleton.summarization_model).to eq("claude-sonnet-5-5")
        end

        it "answers a JSON client with 409 and names the column" do
          AdminSetting.singleton.update!(summary_batch_enabled: true)

          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                summary_batch_enabled: false,
                expected: {summary_batch_enabled: false}
              }
            },
            as: :json

          expect(response).to have_http_status(:conflict)
          expect(response.parsed_body.dig("error", "code")).to eq("stale_write")
          expect(response.parsed_body.dig("error", "message")).to include("summary_batch_enabled")
          expect(AdminSetting.singleton.reload.summary_batch_enabled).to be(true)
        end

        it "applies a submit that carries no expected block at all" do
          patch "/admin/llm_settings", params: {admin_setting: {summary_batch_enabled: true}}

          expect(AdminSetting.singleton.reload.summary_batch_enabled).to be(true)
        end
      end
    end

    # @lat: [[llm-summaries#Settings live in the database]]
    describe "candidate OpenRouter choices" do
      it "offers original entries plus exactly the three OpenRouter choices with exact labels when offered" do
        candidate_models = (AdminSetting::SUPPORTED_MODELS + Llm::ModelCatalog::OPENROUTER_ROUTES.values.map(&:label)).uniq
        AdminSetting.singleton.update!(offered_models: candidate_models)

        get "/admin/llm_settings"
        expect(response).to have_http_status(:ok)
        supported = inertia.props[:supported_models]
        expect(supported.length).to eq(12)
        expect(supported.pluck(:id)).to match_array(candidate_models)

        deepseek_pro = supported.find { |m| m[:id] == "Deepseek Pro Latest" }
        expect(deepseek_pro[:label]).to eq("Deepseek Pro Latest")
        expect(deepseek_pro[:selectable]).to be(true)

        deepseek_flash = supported.find { |m| m[:id] == "Deepseek Flash Latest" }
        expect(deepseek_flash[:label]).to eq("Deepseek Flash Latest")
        expect(deepseek_flash[:selectable]).to be(true)

        openrouter_auto = supported.find { |m| m[:id] == "OpenRouter Auto" }
        expect(openrouter_auto[:label]).to eq("OpenRouter Auto")
        expect(openrouter_auto[:selectable]).to be(true)
        expect(supported.pluck(:selectable)).to all(be(true))
      end

      it "saves any candidate model ID without a provider parameter when allowlisted" do
        candidate_list = (AdminSetting::SUPPORTED_MODELS + Llm::ModelCatalog::OPENROUTER_ROUTES.values.map(&:label)).uniq
        stub_const("AdminSetting::SUPPORTED_MODELS", candidate_list)
        AdminSetting.validators_on(:summarization_model).each do |v|
          allow(v).to receive(:delimiter).and_return(candidate_list) if v.is_a?(ActiveModel::Validations::InclusionValidator)
        end

        Llm::ModelCatalog::OPENROUTER_ROUTES.values.map(&:label).uniq.each do |model_choice|
          patch "/admin/llm_settings", params: {admin_setting: {summarization_model: model_choice}}
          expect(response).to redirect_to("/admin/llm_settings")
          expect(flash[:notice]).to eq("Model updated.")
          expect(AdminSetting.singleton.reload.summarization_model).to eq(model_choice)
        end
      end
    end

    # @lat: [[admin-llm-settings-controller-design#Dynamic model catalog and offered model actions]]
    describe "POST /admin/llm_settings/refresh_models" do
      before do
        allow(Llm::OpenRouterModelsService).to receive(:call).and_return([])
        allow(Llm::OpenRouterModelsService).to receive(:decision_models).and_return([])
      end

      it "forces a cache refresh of both call and decision_models and redirects with notice for HTML callers" do
        post "/admin/llm_settings/refresh_models"

        expect(Llm::OpenRouterModelsService).to have_received(:call).with(force_refresh: true)
        expect(Llm::OpenRouterModelsService).to have_received(:decision_models).with(force_refresh: true)
        expect(response).to redirect_to("/admin/llm_settings")
        expect(flash[:notice]).to eq("OpenRouter model list refreshed.")
      end

      it "forces a cache refresh and renders supported_models for JSON callers" do
        post "/admin/llm_settings/refresh_models", headers: {"ACCEPT" => "application/json"}

        expect(Llm::OpenRouterModelsService).to have_received(:call).with(force_refresh: true)
        expect(Llm::OpenRouterModelsService).to have_received(:decision_models).with(force_refresh: true)
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["supported_models"]).to be_an(Array)
        expect(response.parsed_body["supported_models"].length).to eq(12)
      end
    end

    # @lat: [[admin-llm-settings-controller-design#Dynamic model catalog and offered model actions]]
    describe "POST /admin/llm_settings/add_model" do
      context "with a recognized OpenRouter model" do
        it "adds the model to offered_models and redirects with notice for HTML callers" do
          new_model = {id: "meta-llama/llama-3-70b-instruct", label: "Llama 3 70B", supports_reasoning: false}
          allow(Llm::OpenRouterModelsService).to receive(:call).and_return([new_model])
          allow(Llm::OpenRouterModelsService).to receive(:lookup).and_return(nil)
          allow(Llm::OpenRouterModelsService).to receive(:lookup).with(new_model[:id], any_args).and_return(new_model)

          post "/admin/llm_settings/add_model", params: {model_id: new_model[:id]}

          expect(response).to redirect_to("/admin/llm_settings")
          expect(flash[:notice]).to eq("Model added to offered list.")
          setting = AdminSetting.singleton.reload
          expect(setting.offered_models_list).to include(new_model[:id])
          expect(setting.updated_by).to eq(admin)
        end

        it "adds the model and renders supported_models for JSON callers" do
          new_model = {id: "meta-llama/llama-3-70b-instruct", label: "Llama 3 70B", supports_reasoning: false}
          allow(Llm::OpenRouterModelsService).to receive(:call).and_return([new_model])
          allow(Llm::OpenRouterModelsService).to receive(:lookup).and_return(nil)
          allow(Llm::OpenRouterModelsService).to receive(:lookup).with(new_model[:id], any_args).and_return(new_model)

          post "/admin/llm_settings/add_model",
            params: {model_id: new_model[:id]},
            headers: {"ACCEPT" => "application/json"}

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body["supported_models"].pluck("id")).to include(new_model[:id])
          expect(AdminSetting.singleton.reload.offered_models_list).to include(new_model[:id])
        end
      end

      context "re-adding a previously removed baseline model" do
        before do
          AdminSetting.singleton.update!(
            offered_models: AdminSetting::SUPPORTED_MODELS - ["Deepseek Flash Latest"]
          )
          allow(Llm::OpenRouterModelsService).to receive(:call).and_return([])
          allow(Llm::OpenRouterModelsService).to receive(:lookup).and_return(nil)
        end

        it "successfully re-adds the baseline model" do
          post "/admin/llm_settings/add_model", params: {model_id: "Deepseek Flash Latest"}

          expect(response).to redirect_to("/admin/llm_settings")
          expect(flash[:notice]).to eq("Model added to offered list.")
          expect(AdminSetting.singleton.reload.offered_models_list).to include("Deepseek Flash Latest")
        end
      end

      context "with an unrecognized model ID" do
        before do
          allow(Llm::OpenRouterModelsService).to receive(:call).and_return([])
          allow(Llm::OpenRouterModelsService).to receive(:lookup).and_return(nil)
        end

        it "redirects with inertia errors for HTML callers" do
          post "/admin/llm_settings/add_model", params: {model_id: "unknown/model"}

          expect(response).to redirect_to("/admin/llm_settings")
          inertia_errors = session[:inertia_errors] || {}
          expect(inertia_errors[:offered_models] || inertia_errors["offered_models"]).to be_present
          expect(AdminSetting.singleton.reload.offered_models_list).not_to include("unknown/model")
        end

        it "returns 422 with json error for JSON callers" do
          post "/admin/llm_settings/add_model",
            params: {model_id: "unknown/model"},
            headers: {"ACCEPT" => "application/json"}

          expect(response).to have_http_status(:unprocessable_content)
          expect(response.parsed_body["error"]).to be_present
        end
      end
    end

    # @lat: [[admin-llm-settings-controller-design#Dynamic model catalog and offered model actions]]
    describe "DELETE /admin/llm_settings/remove_model" do
      context "with a removable non-active model" do
        it "removes the model from offered_models and redirects with notice for HTML callers" do
          delete "/admin/llm_settings/remove_model", params: {model_id: "Deepseek Flash Latest"}

          expect(response).to redirect_to("/admin/llm_settings")
          expect(flash[:notice]).to eq("Model removed from offered list.")
          setting = AdminSetting.singleton.reload
          expect(setting.offered_models_list).not_to include("Deepseek Flash Latest")
          expect(setting.updated_by).to eq(admin)
        end

        it "removes the model and renders supported_models for JSON callers" do
          delete "/admin/llm_settings/remove_model",
            params: {model_id: "Deepseek Flash Latest"},
            headers: {"ACCEPT" => "application/json"}

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body["supported_models"].pluck("id")).not_to include("Deepseek Flash Latest")
          expect(AdminSetting.singleton.reload.offered_models_list).not_to include("Deepseek Flash Latest")
        end
      end

      context "attempting to remove the active summarization model" do
        it "refuses to remove with inertia error for HTML callers" do
          delete "/admin/llm_settings/remove_model", params: {model_id: "claude-haiku-5-5"}

          expect(response).to redirect_to("/admin/llm_settings")
          inertia_errors = session[:inertia_errors] || {}
          expect(inertia_errors[:offered_models] || inertia_errors["offered_models"]).to include("cannot remove a model that is currently active")
          expect(AdminSetting.singleton.reload.offered_models_list).to include("claude-haiku-5-5")
        end

        it "refuses to remove with 422 for JSON callers" do
          delete "/admin/llm_settings/remove_model",
            params: {model_id: "claude-haiku-5-5"},
            headers: {"ACCEPT" => "application/json"}

          expect(response).to have_http_status(:unprocessable_content)
          expect(response.parsed_body["error"]).to include("cannot remove a model that is currently active")
        end
      end

      context "attempting to remove the active classification model" do
        before do
          AdminSetting.singleton.update!(classification_model: "claude-sonnet-5-5")
        end

        it "refuses to remove with inertia error for HTML callers" do
          delete "/admin/llm_settings/remove_model", params: {model_id: "claude-sonnet-5-5"}

          expect(response).to redirect_to("/admin/llm_settings")
          inertia_errors = session[:inertia_errors] || {}
          expect(inertia_errors[:offered_models] || inertia_errors["offered_models"]).to include("cannot remove a model that is currently active")
        end
      end
    end

    describe "PATCH /admin/llm_settings — specialized models (decision_model and extraction_model)" do
      it "updates decision_model to Jev Latest, redirects with flash notice, and updates singleton" do
        patch "/admin/llm_settings",
          params: {admin_setting: {decision_model: "Jev Latest"}}

        expect(response).to redirect_to("/admin/llm_settings")
        expect(flash[:notice]).to eq("Model updated.")

        expect(AdminSetting.singleton.reload.decision_model).to eq("Jev Latest")
        expect(AdminSetting.singleton.updated_by_id).to eq(admin.id)
      end

      it "updates extraction_model to claude-haiku-5-5, redirects with flash notice, and updates singleton" do
        patch "/admin/llm_settings",
          params: {admin_setting: {extraction_model: "claude-haiku-5-5"}}

        expect(response).to redirect_to("/admin/llm_settings")
        expect(flash[:notice]).to eq("Model updated.")

        expect(AdminSetting.singleton.reload.extraction_model).to eq("claude-haiku-5-5")
        expect(AdminSetting.singleton.updated_by_id).to eq(admin.id)
      end

      it "includes decision_model and extraction_model in successful JSON responses" do
        patch "/admin/llm_settings",
          params: {admin_setting: {decision_model: "Jev Latest", extraction_model: "ScaleDown Extract Latest"}},
          headers: {"ACCEPT" => "application/json"}

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["decision_model"]).to eq("Jev Latest")
        expect(json["extraction_model"]).to eq("ScaleDown Extract Latest")
      end
    end

    describe "PATCH /admin/llm_settings — specialized model validation failures" do
      it "rejects unrecognized decision_model and attaches error to decision_model" do
        patch "/admin/llm_settings",
          params: {admin_setting: {decision_model: "unrecognized/decision-model"}}

        expect(response).to redirect_to("/admin/llm_settings")
        errors = admin_setting_errors_from_session
        expect(errors[:decision_model] || errors["decision_model"]).to eq(
          "Model not recognized. Choose from the list."
        )
        expect(AdminSetting.singleton.reload.decision_model).to eq("ScaleDown Classify Latest")
      end

      it "rejects unrecognized extraction_model and attaches error to extraction_model" do
        patch "/admin/llm_settings",
          params: {admin_setting: {extraction_model: "unrecognized/extraction-model"}}

        expect(response).to redirect_to("/admin/llm_settings")
        errors = admin_setting_errors_from_session
        expect(errors[:extraction_model] || errors["extraction_model"]).to eq(
          "Model not recognized. Choose from the list."
        )
        expect(AdminSetting.singleton.reload.extraction_model).to eq("ScaleDown Extract Latest")
      end

      it "returns 422 with json error message for JSON callers on invalid decision_model" do
        patch "/admin/llm_settings",
          params: {admin_setting: {decision_model: "unrecognized/decision-model"}},
          headers: {"ACCEPT" => "application/json"}

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body.dig("error", "message")).to eq("Model not recognized.")
      end
    end

    describe "PATCH /admin/llm_settings — stale-write detection on specialized models" do
      it "detects stale decision_model write and redirects with conflict error for HTML callers" do
        patch "/admin/llm_settings",
          params: {
            admin_setting: {
              decision_model: "Jev Latest",
              expected: {decision_model: "Old Non-Existent"}
            }
          }

        expect(response).to redirect_to("/admin/llm_settings")
        errors = admin_setting_errors_from_session
        expect(errors[:decision_model] || errors["decision_model"]).to include(
          "Someone else changed this to ScaleDown Classify Latest since you loaded the page."
        )
      end

      it "detects stale extraction_model write and returns 409 conflict for JSON callers" do
        patch "/admin/llm_settings",
          params: {
            admin_setting: {
              extraction_model: "claude-haiku-5-5",
              expected: {extraction_model: "Old Extraction"}
            }
          },
          headers: {"ACCEPT" => "application/json"}

        expect(response).to have_http_status(:conflict)
        expect(response.parsed_body.dig("error", "code")).to eq("stale_write")
        expect(response.parsed_body.dig("error", "message")).to include(
          "extraction_model is now ScaleDown Extract Latest, not the value you sent as expected."
        )
      end
    end

    describe "GET /admin/llm_settings — retired specialized models" do
      it "renders a stored but no-longer-offered decision_model with selectable: false" do
        AdminSetting.singleton.update_column(:decision_model, "legacy-decision-model")

        get "/admin/llm_settings"

        expect(response).to have_http_status(:ok)
        decision_models = inertia.props[:supported_decision_models]
        retired = decision_models.find { |m| m[:id] == "legacy-decision-model" }

        expect(retired).to be_present
        expect(retired[:selectable]).to be(false)
        expect(retired[:label]).to include("legacy-decision-model — no longer offered")
        expect(retired[:supports_reasoning]).to be(false)
      end

      it "renders a stored but no-longer-offered extraction_model with selectable: false" do
        AdminSetting.singleton.update_column(:extraction_model, "legacy-extraction-model")

        get "/admin/llm_settings"

        expect(response).to have_http_status(:ok)
        extraction_models = inertia.props[:supported_extraction_models]
        retired = extraction_models.find { |m| m[:id] == "legacy-extraction-model" }

        expect(retired).to be_present
        expect(retired[:selectable]).to be(false)
        expect(retired[:label]).to include("legacy-extraction-model — no longer offered")
      end
    end

    describe "Specialized Models Adversarial Scenarios" do
      let(:setting) { AdminSetting.singleton }

      before do
        setting.update!(
          summarization_model: "claude-haiku-5-5",
          classification_model: "claude-haiku-5-5",
          decision_model: "ScaleDown Classify Latest",
          extraction_model: "ScaleDown Extract Latest",
          offered_models: AdminSetting::SUPPORTED_MODELS,
          summary_batch_enabled: false
        )
      end

      describe "Adversarial Dimension 1: Concurrency and Stale-Write Conflicts" do
        it "returns 409 conflict when both decision_model and extraction_model have stale expected values simultaneously" do
          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                decision_model: "Jev Latest",
                extraction_model: "claude-haiku-5-5",
                expected: {
                  decision_model: "Perplexity Decider Latest",
                  extraction_model: "Old Non-Existent Extraction"
                }
              }
            },
            as: :json

          expect(response).to have_http_status(:conflict)
          expect(response.parsed_body.dig("error", "code")).to eq("stale_write")
          message = response.parsed_body.dig("error", "message")
          expect(message).to include("decision_model is now ScaleDown Classify Latest")
          expect(message).to include("extraction_model is now ScaleDown Extract Latest")
          expect(setting.reload.decision_model).to eq("ScaleDown Classify Latest")
          expect(setting.reload.extraction_model).to eq("ScaleDown Extract Latest")
        end

        it "redirects with inertia session error hash containing both fields for HTML callers" do
          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                decision_model: "Jev Latest",
                extraction_model: "claude-haiku-5-5",
                expected: {
                  decision_model: "Perplexity Decider Latest",
                  extraction_model: "Old Non-Existent Extraction"
                }
              }
            }

          expect(response).to redirect_to("/admin/llm_settings")
          errors = admin_setting_errors_from_session
          expect(errors[:decision_model] || errors["decision_model"]).to include("ScaleDown Classify Latest")
          expect(errors[:extraction_model] || errors["extraction_model"]).to include("ScaleDown Extract Latest")
        end

        it "updates decision_model cleanly when expected matches current database state" do
          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                decision_model: "Jev Latest",
                expected: {decision_model: "ScaleDown Classify Latest"}
              }
            },
            as: :json

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body["decision_model"]).to eq("Jev Latest")
          expect(setting.reload.decision_model).to eq("Jev Latest")
          expect(setting.updated_by_id).to eq(admin.id)
        end

        it "permits unconditional update when expected block is omitted" do
          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                decision_model: "Perplexity Decider Latest"
              }
            },
            as: :json

          expect(response).to have_http_status(:ok)
          expect(setting.reload.decision_model).to eq("Perplexity Decider Latest")
        end
      end

      describe "Adversarial Dimension 2: Independent Field Updates and Isolation" do
        it "updating decision_model does not produce false conflicts on unchanged chat models" do
          setting.update!(
            summarization_model: "claude-sonnet-5-5",
            classification_model: "Gemini Argon Latest",
            decision_model: "ScaleDown Classify Latest"
          )

          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                decision_model: "Jev Latest",
                expected: {
                  decision_model: "ScaleDown Classify Latest",
                  summarization_model: "claude-sonnet-5-5",
                  classification_model: "Gemini Argon Latest"
                }
              }
            },
            as: :json

          expect(response).to have_http_status(:ok)
          setting.reload
          expect(setting.decision_model).to eq("Jev Latest")
          expect(setting.summarization_model).to eq("claude-sonnet-5-5")
          expect(setting.classification_model).to eq("Gemini Argon Latest")
        end

        it "updating extraction_model does not mutate decision_model or chat models" do
          setting.update!(
            summarization_model: "claude-opus-5-5",
            classification_model: "Opus Latest",
            decision_model: "Perplexity Decider Latest",
            extraction_model: "ScaleDown Extract Latest"
          )

          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                extraction_model: "claude-haiku-5-5",
                expected: {extraction_model: "ScaleDown Extract Latest"}
              }
            },
            as: :json

          expect(response).to have_http_status(:ok)
          setting.reload
          expect(setting.extraction_model).to eq("claude-haiku-5-5")
          expect(setting.decision_model).to eq("Perplexity Decider Latest")
          expect(setting.summarization_model).to eq("claude-opus-5-5")
          expect(setting.classification_model).to eq("Opus Latest")
        end

        it "updating summarization_model does not mutate decision_model or extraction_model" do
          setting.update!(
            summarization_model: "claude-haiku-5-5",
            decision_model: "Jev Latest",
            extraction_model: "ScaleDown Extract Latest"
          )

          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                summarization_model: "claude-sonnet-5-5",
                expected: {summarization_model: "claude-haiku-5-5"}
              }
            },
            as: :json

          expect(response).to have_http_status(:ok)
          setting.reload
          expect(setting.summarization_model).to eq("claude-sonnet-5-5")
          expect(setting.decision_model).to eq("Jev Latest")
          expect(setting.extraction_model).to eq("ScaleDown Extract Latest")
        end

        it "submitting unchanged values returns unchanged notice and does not mutate timestamps" do
          original_time = setting.updated_at

          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                decision_model: setting.decision_model,
                extraction_model: setting.extraction_model
              }
            }

          expect(response).to redirect_to("/admin/llm_settings")
          expect(flash[:notice]).to eq("Nothing to update — no setting was changed.")
          expect(setting.reload.updated_at).to be_within(0.001.seconds).of(original_time)
        end
      end

      describe "Adversarial Dimension 3: Single-Pass Catalog Prefetching" do
        it "calls OpenRouterModelsService.call and .decision_models at most once per show request" do
          mock_chat_models = (1..10).map { |i| {id: "mock/chat-#{i}", label: "Chat #{i}", supports_reasoning: false} }
          mock_decision_models = (1..10).map { |i| {id: "mock/decision-#{i}", label: "Decision #{i}", supports_reasoning: false, mode: :decision} }

          allow(Llm::OpenRouterModelsService).to receive(:call).and_return(mock_chat_models)
          allow(Llm::OpenRouterModelsService).to receive(:decision_models).and_return(mock_decision_models)

          expect(Llm::OpenRouterModelsService).to receive(:call).at_most(:once)
          expect(Llm::OpenRouterModelsService).to receive(:decision_models).at_most(:once)

          get "/admin/llm_settings"

          expect(response).to have_http_status(:ok)
          expect(inertia).to render_component("admin/LlmSettings")
          expect(inertia.props[:supported_models]).to be_an(Array)
          expect(inertia.props[:supported_decision_models]).to be_an(Array)
          expect(inertia.props[:supported_extraction_models]).to be_an(Array)
          expect(inertia.props[:available_openrouter_models]).to be_an(Array)
        end

        it "does not trigger redundant service calls across multiple sequential requests" do
          mock_chat_models = (1..10).map { |i| {id: "mock/chat-#{i}", label: "Chat #{i}", supports_reasoning: false} }
          mock_decision_models = (1..10).map { |i| {id: "mock/decision-#{i}", label: "Decision #{i}", supports_reasoning: false, mode: :decision} }

          allow(Llm::OpenRouterModelsService).to receive(:call).and_return(mock_chat_models)
          allow(Llm::OpenRouterModelsService).to receive(:decision_models).and_return(mock_decision_models)

          expect(Llm::OpenRouterModelsService).to receive(:call).at_most(3).times
          expect(Llm::OpenRouterModelsService).to receive(:decision_models).at_most(3).times

          3.times do
            get "/admin/llm_settings"
            expect(response).to have_http_status(:ok)
            expect(inertia).to render_component("admin/LlmSettings")
          end
        end
      end

      describe "Adversarial Dimension 4: Forced Refresh and Option Serialization on Mutation Actions" do
        before do
          allow(Llm::OpenRouterModelsService).to receive(:call).and_return([])
          allow(Llm::OpenRouterModelsService).to receive(:decision_models).and_return([])
        end

        it "forces refresh on both call and decision_models on POST /admin/llm_settings/refresh_models (HTML)" do
          post "/admin/llm_settings/refresh_models"

          expect(Llm::OpenRouterModelsService).to have_received(:call).with(force_refresh: true)
          expect(Llm::OpenRouterModelsService).to have_received(:decision_models).with(force_refresh: true)
          expect(response).to redirect_to("/admin/llm_settings")
          expect(flash[:notice]).to eq("OpenRouter model list refreshed.")
        end

        it "returns full serialized model options in JSON on refresh_models" do
          post "/admin/llm_settings/refresh_models", as: :json

          expect(Llm::OpenRouterModelsService).to have_received(:call).with(force_refresh: true)
          expect(Llm::OpenRouterModelsService).to have_received(:decision_models).with(force_refresh: true)
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body).to have_key("supported_models")
          expect(response.parsed_body).to have_key("supported_decision_models")
          expect(response.parsed_body).to have_key("supported_extraction_models")
        end

        it "returns full serialized model options in JSON on add_model" do
          new_model = {id: "meta-llama/llama-3-70b-instruct", label: "Llama 3 70B", supports_reasoning: false}
          allow(Llm::OpenRouterModelsService).to receive(:call).and_return([new_model])
          allow(Llm::OpenRouterModelsService).to receive(:lookup).with(new_model[:id], any_args).and_return(new_model)

          post "/admin/llm_settings/add_model",
            params: {model_id: "meta-llama/llama-3-70b-instruct"},
            as: :json

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body).to have_key("supported_models")
          expect(response.parsed_body).to have_key("supported_decision_models")
          expect(response.parsed_body).to have_key("supported_extraction_models")
        end

        it "returns full serialized model options in JSON on remove_model" do
          new_model = {id: "meta-llama/llama-3-70b-instruct", label: "Llama 3 70B", supports_reasoning: false}
          allow(Llm::OpenRouterModelsService).to receive(:call).and_return([new_model])
          allow(Llm::OpenRouterModelsService).to receive(:lookup).with(new_model[:id], any_args).and_return(new_model)

          post "/admin/llm_settings/add_model",
            params: {model_id: "meta-llama/llama-3-70b-instruct"},
            as: :json

          delete "/admin/llm_settings/remove_model",
            params: {model_id: "meta-llama/llama-3-70b-instruct"},
            as: :json

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body).to have_key("supported_models")
          expect(response.parsed_body).to have_key("supported_decision_models")
          expect(response.parsed_body).to have_key("supported_extraction_models")
        end
      end

      describe "Adversarial Dimension 5: Retired Models and Active Decision in Classification" do
        it "renders an active decision model stored in classification_model as selectable without retirement label" do
          setting.update!(classification_model: "ScaleDown Classify Latest")

          get "/admin/llm_settings"

          expect(response).to have_http_status(:ok)
          supported = inertia.props[:supported_models]
          active_entry = supported.find { |m| m[:id] == "ScaleDown Classify Latest" }

          expect(active_entry).to be_present
          expect(active_entry[:selectable]).to be(true)
          expect(active_entry[:supports_reasoning]).to be(false)
          expect(active_entry[:label]).not_to include("no longer offered")
        end

        it "allows other fields to update without failing validation due to a retired decision model" do
          setting.update_column(:decision_model, "legacy-retired/decision-model")

          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                extraction_model: "claude-haiku-5-5",
                expected: {extraction_model: "ScaleDown Extract Latest"}
              }
            },
            as: :json

          expect(response).to have_http_status(:ok)
          setting.reload
          expect(setting.extraction_model).to eq("claude-haiku-5-5")
          expect(setting.decision_model).to eq("legacy-retired/decision-model")
        end

        it "allows other fields to update without failing validation due to a retired extraction model" do
          setting.update_column(:extraction_model, "legacy-retired/extraction-model")

          patch "/admin/llm_settings",
            params: {
              admin_setting: {
                decision_model: "Jev Latest",
                expected: {decision_model: "ScaleDown Classify Latest"}
              }
            },
            as: :json

          expect(response).to have_http_status(:ok)
          setting.reload
          expect(setting.decision_model).to eq("Jev Latest")
          expect(setting.extraction_model).to eq("legacy-retired/extraction-model")
        end
      end

      describe "Adversarial Dimension 6: Dynamic Catalog Merging and Canonical Slug Deduplication" do
        before do
          chat_catalog = [
            {id: "provider/alpha-chat", label: "Alpha Chat", supports_reasoning: true},
            {id: "provider/shared-model", label: "Shared Model", supports_reasoning: true},
            {id: "scaledown/classify-1", label: "ScaleDown Classify 1", supports_reasoning: false},
            {id: "scaledown/extract", label: "ScaleDown Extract", supports_reasoning: false}
          ]
          decision_catalog = [
            {id: "provider/beta-decision", label: "Beta Decision", supports_reasoning: false, mode: :decision},
            {id: "provider/shared-model", label: "Shared Model Decision", supports_reasoning: false, mode: :decision},
            {id: "~typesafe/jev-latest", label: "Jev Upstream Slug", supports_reasoning: false, mode: :decision}
          ]
          allow(Llm::OpenRouterModelsService).to receive(:call).and_return(chat_catalog)
          allow(Llm::OpenRouterModelsService).to receive(:decision_models).and_return(decision_catalog)
        end

        it "merges catalogs, deduplicates shared entries, and excludes canonical OpenRouter slugs for offered Latest aliases" do
          get "/admin/llm_settings"

          expect(response).to have_http_status(:ok)
          expect(inertia).to render_component("admin/LlmSettings")
          available = inertia.props[:available_openrouter_models]
          available_ids = available.pluck(:id)

          expect(available_ids).to include("provider/alpha-chat", "provider/beta-decision", "provider/shared-model")
          expect(available_ids).not_to include("scaledown/classify-1")
          expect(available_ids).not_to include("scaledown/extract")
          expect(available_ids).not_to include("~typesafe/jev-latest")

          beta_entry = available.find { |m| m[:id] == "provider/beta-decision" }
          expect(beta_entry[:label]).to eq("Beta Decision")
          expect(beta_entry[:supports_reasoning]).to be(false)

          shared_entries = available.select { |m| m[:id] == "provider/shared-model" }
          expect(shared_entries.size).to eq(1)

          alpha_entry = available.find { |m| m[:id] == "provider/alpha-chat" }
          expect(alpha_entry[:supports_reasoning]).to be(true)
        end

        it "excludes models that are already present in offered_models" do
          setting.update!(
            offered_models: AdminSetting::SUPPORTED_MODELS + ["provider/alpha-chat"]
          )

          get "/admin/llm_settings"

          expect(response).to have_http_status(:ok)
          expect(inertia).to render_component("admin/LlmSettings")
          available = inertia.props[:available_openrouter_models]
          available_ids = available.pluck(:id)

          expect(available_ids).not_to include("provider/alpha-chat")
          expect(available_ids).to include("provider/beta-decision")
        end

        it "sorts candidates case-insensitively by label and id" do
          get "/admin/llm_settings"

          expect(response).to have_http_status(:ok)
          expect(inertia).to render_component("admin/LlmSettings")
          available = inertia.props[:available_openrouter_models]

          labels_and_ids = available.map { |m| [m[:label].downcase, m[:id]] }
          expect(labels_and_ids).to eq(labels_and_ids.sort)
        end
      end
    end
  end
end
