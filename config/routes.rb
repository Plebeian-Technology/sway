# typed: strict

Rails.application.routes.draw do
  default_url_options protocol: :https

  # ServerRendering
  root 'home#index'

  get 's/:id' => 'shortener/shortened_urls#show'
  get 'invite/:user_id/:invite_uuid', action: 'show', controller: :invites
  get 'invites/:user_id/:invite_uuid', action: 'show', controller: :invites

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  resources :sway_registration, only: %i[index create]

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  resources :bills
  resources :bill_of_the_week, only: %i[index]
  resources :bill_scores, only: %i[show]
  resources :bill_score_districts, only: %i[show]
  resources :districts, only: %i[index]
  resources :influence, only: %i[index]
  resources :legislators, only: %i[index show]
  resources :legislator_votes, only: %i[index show create update]
  resources :organizations, only: %i[index show create update]
  resources :organization_bill_positions, only: %i[index show create]
  resources :sway_locales, only: %i[index show]
  resources :user_districts, only: %i[index]
  resources :user_legislators, only: %i[index create]
  resources :user_legislator_scores, only: %i[index show]
  resources :user_votes, only: %i[index show create]

  resources :phone_verification, only: %i[create update]

  namespace :buckets do
    resources :assets, only: %i[create]
  end

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
  end
end
