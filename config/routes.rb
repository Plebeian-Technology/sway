Rails.application.routes.draw do
  if Rails.env.test?
    post "/__query_parameter_carry/organizations",
      to: "test/query_parameter_carry_probe#redirect_to_organizations"
    post "/__query_parameter_carry/organizations_plain",
      to: "test/query_parameter_carry_probe#redirect_to_organizations_without_tab"
    post "/__query_parameter_carry/bills",
      to: "test/query_parameter_carry_probe#redirect_to_bills"
    post "/__query_parameter_carry/bills_clear",
      to: "test/query_parameter_carry_probe#redirect_to_bills_with_clear"
    post "/__query_parameter_carry/bills_repeated_clear",
      to: "test/query_parameter_carry_probe#redirect_to_bills_with_repeated_clear"
    post "/__query_parameter_carry/creator/:bill_id",
      to: "test/query_parameter_carry_probe#redirect_to_creator"
    post "/__query_parameter_carry/creator/:bill_id/empty_list",
      to: "test/query_parameter_carry_probe#redirect_to_creator_with_empty_list"
    get "/organizations/__query_parameter_carry_target",
      to: "test/query_parameter_carry_probe#show_target"
    get "/organizations/__query_parameter_carry_get_redirect",
      to: "test/query_parameter_carry_probe#redirect_to_organizations_without_tab"
    get "/bills/__query_parameter_carry_target",
      to: "test/query_parameter_carry_probe#show_target"
    get "/admin/bill_creator/:bill_id/__query_parameter_carry_target",
      to: "test/query_parameter_carry_probe#show_target"
    get "/admin/bill_creator/:bill_id/__query_parameter_carry_get_redirect",
      to: "test/query_parameter_carry_probe#redirect_to_creator"
    get "/__query_parameter_carry_target",
      to: "test/query_parameter_carry_probe#show_target"
    get "/sessions/__query_parameter_carry_target",
      to: "test/query_parameter_carry_probe#show_target"
    post "/__query_parameter_carry/excluded_target",
      to: "test/query_parameter_carry_probe#redirect_to_excluded_destination"
    post "/__query_parameter_carry/unsafe_location",
      to: "test/query_parameter_carry_probe#redirect_to_location"
    post "/__query_parameter_carry/non_redirect",
      to: "test/query_parameter_carry_probe#render_conflict"

    require Rails.root.join("lib", "navigation_route_exclusions")
    NavigationRouteExclusions::EXCLUDED_PREFIXES.each do |prefix|
      get "#{prefix}/__query_parameter_carry_probe",
        to: "test/query_parameter_carry_probe#redirect_to_excluded_target"
    end

    namespace :test do
      resources :sessions, only: [:create]
    end

    # @lat: [[activity-log-flash-transport]]
    get "/__inertia_flash_probe/trigger", to: "inertia_flash_probe#trigger"
    # @lat: [[activity-log-flash-transport]]
    get "/__inertia_flash_error_probe/trigger", to: "inertia_flash_probe#trigger_flash_error"
  end

  # @lat: [[well-known-webauthn-route#Why the WebAuthn metadata is selected at request time]]
  get ".well-known/webauthn", action: "index", controller: :well_known

  # @lat: [[well-known-controller-notes#Why both hosts are authoritative]]
  get ".well-known/apple-app-site-association",
    to: "well_known#aasa",
    defaults: {
      format: :json
    }
  get ".well-known/assetlinks.json",
    to: "well_known#assetlinks",
    defaults: {
      format: :json
    }

  get "sitemap.xml", action: "index", controller: :sitemap

  # @lat: [[route-url-default-options#Route redraws use the shared URL defaults]]
  default_url_options(
    {protocol: ENV.fetch("APP_PROTOCOL", "https")}
      .merge(Rails.application.config.x.default_url_options || {})
  )

  post "csp-report", to: "csp_reports#create"

  # @lat: [[public-disclosure-pages#Public disclosure pages#Why the component tests are the only cover for the text]]
  get "download", to: "marketing#mobile_download", as: :mobile_download

  # @lat: [[public-disclosure-pages#Public disclosure pages#Why the component tests are the only cover for the text]]
  get "sms", to: "marketing#sms", as: :sms_disclosure
  get "privacy", to: "marketing#privacy", as: :privacy_policy
  get "terms", to: "marketing#terms", as: :terms_of_service

  # @lat: [[release-git-fallback-and-caching#Why Version.tsx's "Built from" cell says what it says]]
  get "version", to: "meta#version", as: :version
  get "licenses", to: "meta#licenses", as: :licenses

  root "home#index"

  get "s/:id" => "shortener/shortened_urls#show"
  get "invite/:user_id/:invite_uuid",
    action: :show,
    controller: :invites,
    as: "invite"
  get "invites/:user_id/:invite_uuid",
    action: :show,
    controller: :invites,
    as: "invites"

  get "up" => "rails/health#show", :as => :rails_health_check

  # @lat: [[bill-creator-shell#The Bill Creator shell#Why tab URLs retain legacy compatibility]]
  get "/admin/bill_creator/new" => "bills#new", :as => :new_bill_creator
  get "/admin/bill_creator/:id/creator" => "bills#edit",
    :as => :creator_bill_creator,
    :defaults => {bill_creator_tab: "creator"}
  get "/admin/bill_creator/:id/schedule" => "bills#edit",
    :as => :schedule_bill_creator,
    :defaults => {bill_creator_tab: "schedule"}
  get "/admin/bill_creator/:id/pipeline" => "bills#edit",
    :as => :pipeline_bill_creator,
    :defaults => {bill_creator_tab: "pipeline"}
  get "/admin/bill_creator/:id/summary" => "bills#edit",
    :as => :summary_bill_creator,
    :defaults => {bill_creator_tab: "summary"}
  get "/admin/bill_creator/:id/positions" => "bills#edit",
    :as => :positions_bill_creator,
    :defaults => {bill_creator_tab: "positions"}

  # @lat: [[bill-creator-shell#The Bill Creator shell#Why tab URLs retain legacy compatibility]]
  get "/admin/bill_creator/:id/edit",
    to: redirect(status: 302) { |params, req|
      parsed = Rack::Utils.parse_query(req.query_string)
      tab_name = (parsed.key?("bill_creator_tab") ? parsed["bill_creator_tab"] : parsed["tab_key"]).to_s
      parsed.delete("bill_creator_tab")
      parsed.delete("tab_key")
      segment = LegacyBillCreatorTabs::URL_SEGMENT_FOR[tab_name] || "creator"
      base = "/admin/bill_creator/#{params[:id]}/#{segment}"
      parsed.empty? ? base : "#{base}?#{Rack::Utils.build_query(parsed)}"
    },
    as: :edit_bill_creator

  get "/admin/bill_creator/:id",
    to: redirect(status: 302) { |params, req|
      qs = req.query_string.presence
      base = "/admin/bill_creator/#{params[:id]}/creator"
      qs ? "#{base}?#{qs}" : base
    }

  # @lat: [[bill-creator-shell#The Bill Creator shell#Why tab URLs retain legacy compatibility]]
  get "bills/new",
    to: redirect(status: 302) { |_params, req|
      qs = req.query_string.presence
      qs ? "/admin/bill_creator/new?#{qs}" : "/admin/bill_creator/new"
    },
    as: :new_bill
  get "bills/:id/edit",
    to: redirect(status: 302) { |params, req|
      qs = req.query_string.presence
      base = "/admin/bill_creator/#{params[:id]}/edit"
      qs ? "#{base}?#{qs}" : base
    },
    as: :edit_bill

  resources :bills, except: %i[new edit] do
    member do
      post :generate_summary
      # @lat: [[bill-creator-summary-tab#Regeneration records its audit entry after enqueue]]
      post :regenerate_summary
      # @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Supplemental testimony is replaced, never appended]]
      patch :supplemental_testimony
      patch :testimony_letter_stance
      post :approve_org_position
      # @lat: [[bill-llm-schema-validation-design#What the summary schema is shared between]]
      post :paste_summary
      # @lat: [[bill-creator-summary-tab#Planned recoverable summary history]]
      post :restore_summary_revision
    end
    collection do
      post :run_pipeline
      post :sweep_stale_pipeline_runs
    end
    # @lat: [[bills-categories-controller-manual-assignment#Why the count-and-insert is inside with_lock]]
    resources :categories, only: %i[create destroy], module: "bills"
    # @lat: [[testimony-letters#Reading the letters inside a testimony bundle#Browsing constituent testimony in the modal]]
    resources :public_testimony_letters, only: %i[index], module: "bills"
    resources :summary_reports, only: [:create], controller: "bill_summary_reports"
    # @lat: [[bill-creator-positions-tab#The acknowledgement returns to the only tab that offers it]]
    resource :testimony_coverage_acknowledgement, only: [:create]
    # @lat: [[campaign-position-cards#Approving a campaign out of testimony#The draft's content hash is its whole identity]]
    resources :campaigns, only: [:create] do
      collection do
        post :reject_draft
        post :restore_draft
        post :mark_individual_draft
      end
      # @lat: [[campaign-approval#Approving a campaign from a testimony draft#An organization link carries the decision that made it]]
      member do
        post :link_organization
      end
    end
  end

  delete "bills/legislation_pipeline_runs/:id",
    to: "bills#cancel_pipeline_run_bill",
    as: :cancel_pipeline_run_bill
  post "bills/legislation_pipeline_runs/:id/resume",
    to: "bills#resume_pipeline_run",
    as: :resume_pipeline_run
  post "bills/legislation_pipeline_runs/:id/restart",
    to: "bills#restart_pipeline_run",
    as: :restart_pipeline_run

  # @lat: [[inbound-sms#The flag matters even though Twilio enforces opt-out]]
  post "webhooks/twilio/sms",
    to: "webhooks/twilio_messages#create",
    as: :twilio_sms_webhook

  resources :bill_of_the_month, only: %i[index]
  get "bill_of_the_week", to: redirect(path: "/bill_of_the_month"), as: nil
  get "past_bills_of_the_month", to: "bills#past_of_the_month", as: :past_bills_of_the_month
  resources :bill_of_the_month_schedule, only: %i[update]
  # @lat: [[legacy-cookie-json-routes#Cookie-session JSON routes share controllers with bearer API twins]]
  resources :bill_scores, only: %i[show]
  resources :bill_score_districts, only: %i[show]
  resources :districts, only: %i[index]
  get "feed", to: "feed#index", as: :feed
  resources :influence, only: %i[index]
  resources :legislators, only: %i[index show]
  # @lat: [[legacy-cookie-json-routes#Retired top-level read routes and numeric user destroy constraint]]
  resources :legislator_votes, only: %i[create]
  resources :user_legislator_emails, only: %i[create]
  resources :organization_bill_positions, only: %i[index show create destroy]
  resources :sway_locales, only: %i[index show]

  # @lat: [[legislation-pipeline#Runs, resume and restart#The admin surface is index-only]]
  resources :pipeline_runs, only: %i[index] do
    member do
      post :force_fail
    end
    collection do
      delete :orphans, action: :destroy_orphans, as: :destroy_orphans
    end
  end

  # @lat: [[bill-draft-org-positions-controller#Why a malformed id is a 422, not a 404]]
  resources :bill_draft_org_positions, only: %i[update]

  # @lat: [[llm-summaries#LLM bill summaries#Settings live in the database#The settings route is a singleton]]
  resources :sending_service_domains, only: %i[update]
  namespace :admin do
    get "/", to: "index#show", as: :root
    get "/locales", to: "locales#show", as: :locales
    # @lat: [[identity-and-access#The stand-in account borrows a jurisdiction's sample address]]
    patch "/locales/:id", to: "locales#update", as: :locale
    get "/shared_addresses", to: "shared_addresses#show", as: :shared_addresses
    get "/user_address_changes", to: "user_address_changes#show", as: :user_address_changes
    # @lat: [[admin-system-prompts-page#Reading the instructions Sway sends the model]]
    get "/system_prompts", to: "system_prompts#show", as: :system_prompts
    # @lat: [[admin-llm-settings-controller-design#Dynamic model catalog and offered model actions]]
    resource :llm_settings, only: %i[show update] do
      post :refresh_models, on: :collection
      post :add_model, on: :collection
      delete :remove_model, on: :collection
    end
    # @lat: [[bill-categories-spec#What the spec pins#Permanent removal follows deactivation]]
    resources :categories, only: %i[index create update destroy]
    resources :bill_summary_reports, only: %i[index show update]
    get "/registration_funnel", to: "registration_funnel#index", as: :registration_funnel
    resources :partner_reports, only: %i[index show]
    resources :bills, only: [] do
      resources :news_articles, controller: "bill_news_articles", only: %i[index create update]
    end
  end

  # @lat: [[organizations-routing#Organization routes are declared once with nested actions]]
  resources :organizations, only: %i[index show create update] do
    resources :membership_invites,
      only: %i[create destroy],
      controller: "organizations/membership_invites" do
      member do
        get :confirm_accept
        post :accept
      end
    end

    resources :memberships,
      only: %i[show update destroy],
      controller: "organizations/memberships" do
      collection do
        delete :leave
      end
    end
    resources :positions,
      only: %i[create new update destroy],
      controller: "organizations/positions"
    # @lat: [[organization-position-change-controller#Position changes expose decisions without a collection route]]
    resources :position_changes,
      only: %i[update destroy],
      controller: "organizations/position_changes"
  end

  # @lat: [[identity-and-access#Identity and access#Sessions, cookies and bearer tokens]]
  namespace :api do
    namespace :v1 do
      # @lat: [[identity-and-access#Identity and access#The phone number is the account]]
      resources :sessions, only: [] do
        collection do
          post :challenge
          # @lat: [[identity-and-access#Identity and access#The sign-in challenge says which ceremony to run#Mobile passkey ceremonies]]
          post :discoverable_challenge
          post :callback
          post :revoke_all
        end
      end

      # @lat: [[identity-and-access#Identity and access#The admin gate is a lint rule#Adding a passkey re-verifies by SMS first]]
      resources :passkeys, only: %i[create] do
        post :callback, on: :collection
      end

      resources :registrations, only: %i[create] do
        collection do
          post :callback
        end
      end

      post "phone_verification", to: "phone_verifications#request_code"
      post "phone_verification/verify", to: "phone_verifications#verify"

      resources :funnel_events, only: %i[create]

      resources :devices, only: %i[destroy] do
        collection do
          patch :push_token, action: :update_push_token
        end
      end

      get "bootstrap", to: "bootstrap#show"

      # @lat: [[org-notification-cascade-and-defaults#Org-notification cascade and defaults]]
      resources :notification_preferences,
        only: %i[index update],
        param: :key,
        constraints: {key: /[a-z_]+/} do
        collection do
          get :org_defaults, action: :organization_defaults
          patch :org_defaults, action: :update_organization_defaults
        end
      end

      post "notifications/test_push", to: "notifications#test_push"
    end
  end

  scope "api" do
    resources :bills, only: %i[index show]
    resources :bill_of_the_month, only: %i[index]
    get "bill_of_the_week", to: redirect(path: "/api/bill_of_the_month"), as: nil
    resources :bill_scores, only: %i[show]
    resources :bill_score_districts, only: %i[show]
    resources :districts, only: %i[index]
    resources :influence, only: %i[index]
    resources :legislators, only: %i[index show]
    resources :legislator_votes, only: %i[index show]
    resources :organizations, only: %i[index show]
    resources :organization_bill_positions, only: %i[index show]
    resources :sway_locales, only: %i[index show]

    scope "admin" do
      resources :bills, only: %i[create update]
      resources :bill_of_the_month_schedule, only: %i[update]
      resources :legislator_votes, only: %i[create]
      resources :organizations, only: %i[create]
      resources :organization_bill_positions, only: %i[create]
    end
  end

  # @lat: [[public-organizations-endpoint#The public organizations endpoint#What a signed-out reader is never sent]]
  resources :organization_follows, only: %i[create destroy] do
    member { patch :preferences }
  end

  # @lat: [[public-organizations-endpoint#The public organizations endpoint#What a signed-out reader is never sent]]
  namespace :public do
    resources :organizations, only: %i[index show]
  end

  namespace :embed do
    resources :bills, only: [:show]
  end

  # @lat: [[legacy-cookie-json-routes#Retired top-level read routes and numeric user destroy constraint]]
  resources :user_legislators, only: %i[index create]
  resources :user_votes, only: %i[index show create]
  resources :provisional_votes, only: %i[create destroy]
  resources :user_bill_shares, only: %i[create]
  get "bill_shares/:share_uuid", to: "user_bill_shares#show", as: :bill_share

  resources :notifications, only: %i[index] do
    collection do
      patch :settings, to: "notifications#update_settings"
      patch :org_defaults, to: "notifications#update_organization_defaults"
    end
  end
  namespace :notifications do
    resources :push_notifications, only: %i[create]
    resources :push_notification_subscriptions, only: %i[create]
    delete "push_notification_subscriptions",
      to: "push_notification_subscriptions#destroy",
      as: :destroy_push_notification_subscription
  end

  patch "reassignment_notifications/:id/dismiss", to: "representative_reassignments#dismiss"

  resources :phone_verification, only: %i[create update]
  resources :api_keys, only: %i[index create update destroy]
  resources :sway_registration, only: %i[index create]
  get "addresses/autocomplete", to: "addresses#autocomplete"

  # @lat: [[legacy-cookie-json-routes#Retired top-level read routes and numeric user destroy constraint]]
  resources :users, only: %i[destroy], constraints: {id: /\d+/} do
    post :revoke_all_devices, on: :member
  end

  # @lat: [[web-profile-page#Web profile page]]
  get "profile", to: "users/profiles#show", as: :profile

  namespace :users do
    # @lat: [[identity-and-access#Identity and access#The phone number is the account#Email is contact data, not an authentication path]]
    resource :email_verification, only: %i[create update destroy]
    resource :address, only: %i[edit update]

    namespace :webauthn do
      resources :sessions, only: %i[create destroy] do
        post :callback, on: :collection
        # @lat: [[identity-and-access#Identity and access#The sign-in challenge says which ceremony to run#Discoverable callback resolves the credential owner]]
        post :discoverable_challenge, on: :collection
        post :discoverable_callback, on: :collection
      end

      resources :registration, only: %i[create] do
        post :callback, on: :collection
      end
    end

    resources :organization_memberships, only: %i[index]

    # @lat: [[identity-and-access#Identity and access#User JSON exposes only selected fields]]
    resource :preferences, only: %i[update]

    # @lat: [[identity-and-access#Identity and access#The admin gate is a lint rule#Adding a passkey re-verifies by SMS first]]
    resources :passkeys, only: %i[index destroy] do
      collection do
        post :verify_phone
        post :confirm_phone
        post :add_options
        post :add_callback
      end
    end
  end

  match "*path",
    via: :all,
    constraints: ->(request) { request.path.end_with?("/installHook.js.map") },
    to: ->(_env) {
      body = "Not Found"
      [404, {"Content-Type" => "text/plain", "Content-Length" => body.bytesize.to_s}, [body]]
    }

  # @lat: [[bad-request-responses#Bad request responses#A path nothing matches stays on this machine]]
  if Rails.application.config.x.catch_all_enabled.present?
    get "*",
      to: redirect { |_path_params, request| "#{request.protocol}#{request.host_with_port}/" },
      constraints: lambda { |request|
        %w[/rails/ /api/ /vite/ /assets/].none? { |prefix| request.path.start_with?(prefix) }
      }
  end
end
