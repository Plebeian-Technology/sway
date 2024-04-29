# typed: strict

Rails.application.routes.draw do
  default_url_options protocol: :https

  # SSR
  root 'home#index'

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  resources :sway_registration, only: %i[index create]

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  resources :sway_locales
  resources :user_districts
  resources :districts
  resources :bill_score_districts
  resources :bill_scores
  resources :user_legislator_scores
  resources :user_legislators
  resources :legislator_votes
  resources :votes
  resources :legislators
  resources :bills
  resources :user_invites
  resources :user_votes

  # https://github.com/cedarcode/webauthn-rails-demo-app/blob/master/config/routes.rb
  namespace :users do
    namespace :webauthn do
      resources :sessions, only: %i[new create destroy] do
        post :callback, on: :collection
      end

      resources :registration, only: %i[new create] do
        post :callback, on: :collection
      end

      resources :passkeys, only: %i[create destroy] do
        post :callback, on: :collection
      end
    end
  end
end
