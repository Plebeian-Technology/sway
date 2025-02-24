# typed: strict

Rails.application.routes.draw do
  # get "well_known/index"
  get ".well-known/webauthn", action: "index", controller: :well_known

  get "bill_of_the_week_schedule/update"
  default_url_options protocol: :https

  # ServerRendering
  root "home#index"

  # https://web.dev/articles/webauthn-related-origin-requests#browser_support
  # Do this here instead of in a file so that "https://sway.vote" does NOT return this info.
  # Only app.sway.vote should return it

  get "s/:id" => "shortener/shortened_urls#show"
  get "invite/:user_id/:invite_uuid", action: "show", controller: :invites
  get "invites/:user_id/:invite_uuid", action: "show", controller: :invites

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", :as => :rails_health_check

  # Available to current_user
  resources :bills
  resources :bill_of_the_week, only: %i[index]
  resources :bill_of_the_week_schedule, only: %i[update]
  resources :bill_scores, only: %i[show]
  resources :bill_score_districts, only: %i[show]
  resources :districts, only: %i[index]
  resources :influence, only: %i[index]
  resources :legislators, only: %i[index show]
  resources :legislator_votes, only: %i[index show create]
  resources :user_legislator_emails, only: %i[create], controller: :user_legislator_email
  resources :organizations, only: %i[index show create]
  resources :organization_bill_positions, only: %i[index show create]
  resources :sway_locales, only: %i[index show]

  scope "api" do
    resources :bills, only: %i[index show] # no access to new/edit/create/update/destroy
    resources :bill_of_the_week, only: %i[index]
    # resources :bill_of_the_week_schedule, only: %i[update]
    resources :bill_scores, only: %i[show]
    resources :bill_score_districts, only: %i[show]
    resources :districts, only: %i[index]
    resources :influence, only: %i[index] # access only to influence of bearer
    resources :legislators, only: %i[index show]
    resources :legislator_votes, only: %i[index show] # no access to create
    resources :organizations, only: %i[index show] # no access to create
    resources :organization_bill_positions, only: %i[index show] # no access to create
    resources :sway_locales, only: %i[index show]

    scope "admin" do
      resources :bills, only: %i[create update]
      resources :bill_of_the_week_schedule, only: %i[update]
      resources :legislator_votes, only: %i[create]
      resources :organizations, only: %i[create]
      resources :organization_bill_positions, only: %i[create]
    end
  end

  resources :user_districts, only: %i[index]
  resources :user_legislators, only: %i[index create]
  resources :user_legislator_scores, only: %i[index show]
  resources :user_votes, only: %i[index show create]

  namespace :buckets do
    resources :assets, only: %i[create]
  end

  resources :notifications, only: %i[index]
  namespace :notifications do
    resources :push_notifications, only: %i[create]
    resources :push_notification_subscriptions, only: %i[create] do
      collection do
        post "destroy", to: "push_notification_subscriptions#destroy"
      end
    end
    # post :destroy, to: "push_notification_subscriptions#destroy"
  end

  resources :phone_verification, only: %i[create update]
  resources :email_verification, only: %i[create update destroy], controller: :email_verification
  resources :api_keys, only: %i[index create update destroy]
  resources :sway_registration, only: %i[index create]

  # https://github.com/cedarcode/webauthn-rails-demo-app/blob/master/config/routes.rb
  namespace :users do
    namespace :webauthn do
      resources :sessions, only: %i[create destroy] do
        post :callback, on: :collection
      end

      resources :registration, only: %i[create] do
        post :callback, on: :collection
      end
    end

    resources :details, only: %i[create], controller: :user_details
  end

  get "*", to: redirect("https://example.com")
end
