# frozen_string_literal: true

# @lat: [[admin-system-prompts-page#Reading the instructions Sway sends the model]]
# @lat: [[mobile-admin-area#The system prompts screen]]
module Admin
  class SystemPromptsController < ApplicationController
    before_action :verify_is_sway_admin

    def show
      render_inertia_or_json(
        page: Pages::ADMIN_SYSTEM_PROMPTS,
        props: AdminSystemPromptCatalog.new(llm_settings_path: admin_llm_settings_path).as_props
      )
    end
  end
end
