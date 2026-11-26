# frozen_string_literal: true

# @lat: [[admin-hub-index#admin/Index.tsx, the frontend hub page]]
module Admin
  class IndexController < ApplicationController
    before_action :verify_is_sway_admin

    def show
      render_inertia_or_json(
        page: Pages::ADMIN_INDEX,
        props: {
          tools: tools,
          database_health: AdminDatabaseHealth.as_props
        }
      )
    end

    private

    # @lat: [[admin-hub-index#admin/Index.tsx, the frontend hub page]]
    def tools
      items = [
        {
          id: "bill_creator",
          label: "Bill Creator",
          description: "Create and edit bills, run the legislation pipeline, manage organization positions.",
          path: new_bill_creator_path,
          group: "Content",
          external: false
        },
        {
          id: "bill_summary_reports",
          label: "Bill Summary Reports",
          description: "Review, triage, and resolve reader-submitted reports of inaccurate AI bill summaries.",
          path: admin_bill_summary_reports_path,
          group: "Content",
          external: false
        },
        {
          id: "llm_settings",
          label: "LLM Settings",
          description: "Choose the Claude model used for bill summarization (Haiku / Sonnet / Opus).",
          path: admin_llm_settings_path,
          group: "Settings",
          external: false
        },
        {
          id: "system_prompts",
          label: "System Prompts",
          description: "Read the five standing instructions Sway sends the model — one per call site — with the model each is sent under.",
          path: admin_system_prompts_path,
          group: "Settings",
          external: false
        },
        {
          id: "categories",
          label: "Categories",
          description: "Manage the bill category taxonomy — add, rename, and deactivate categories with live bill counts.",
          path: admin_categories_path,
          group: "Content",
          external: false
        },
        {
          id: "pipeline_runs",
          label: "Pipeline Run History",
          description: "Review past legislation-pipeline runs, retry failures, and prune orphaned runs.",
          path: pipeline_runs_path,
          group: "Data",
          external: false
        },
        {
          id: "locales",
          label: "Locales",
          description: "User counts per locale — city, state, and U.S. Congress — including the locales auto-created from registration addresses.",
          path: admin_locales_path,
          group: "Data",
          external: false
        },
        {
          id: "shared_addresses",
          label: "Shared Addresses",
          description: "Addresses more than one registered user has given, with counts only — a signal to review, not a way to browse where people live.",
          path: admin_shared_addresses_path,
          group: "Data",
          external: false
        },
        {
          id: "user_address_changes",
          label: "Address Changes",
          description: "Audit user address switches across districts and locales, including prior vote counts and repeat switchers.",
          path: admin_user_address_changes_path,
          group: "Data",
          external: false
        },
        {
          id: "registration_funnel",
          label: "Registration Funnel",
          description: "Analyze voter registration conversion rates, drop-off friction points, and referral source attribution.",
          path: admin_registration_funnel_path,
          group: "Data",
          external: false
        },
        {
          id: "partner_reports",
          label: "Partner Reports",
          title: "Partner Reports",
          description: "Track newsroom partner article engagement, voter reach, and civic conversion.",
          path: admin_partner_reports_path,
          group: "Data",
          external: false,
          icon: "TrendingUp"
        }
      ]

      if (url = current_user&.beszel_url)
        items << {
          id: "beszel",
          label: "Beszel",
          description: "Monitor host CPU, memory, disk, network, and container metrics in Beszel Hub.",
          path: url,
          group: "Operations",
          external: true
        }
      end

      items
    end
  end
end
