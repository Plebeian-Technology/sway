Rails.application.routes.draw do
  root 'home#index'

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  # Passkey Create - with Bitwarden
  post '/no_auth/passkeys/signup', to: 'no_auth/registrations#create', defaults: { format: :json }

  # SSR
  get 'sign_up', action: :new, controller: 'no_auth/passkeys'

  resources :sway_locales
  resources :user_districts
  resources :districts
  resources :bill_score_districts
  resources :bill_scores
  resources :user_legislator_scores
  resources :user_legislators
  resources :legislator_votes
  resources :votes
  resources :users
  resources :legislators
  resources :bills
  resources :user_invites
  resources :user_votes
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  resources :users, except: [:index]

  # devise_for :users
  devise_for :users, controllers: {
    sessions: 'users/sessions',
    registrations: 'users/registrations'
  }

  devise_scope :user do
    post 'sign_up/new_challenge', to: 'users/registrations#new_challenge', as: :new_user_registration_challenge
    post 'sign_in/new_challenge', to: 'users/sessions#new_challenge', as: :new_user_session_challenge

    post 'reauthenticate/new_challenge', to: 'users/reauthentication#new_challenge',
                                         as: :new_user_reauthentication_challenge
    post 'reauthenticate', to: 'users/reauthentication#reauthenticate', as: :user_reauthentication

    namespace :users do
      resources :passkeys, only: %i[index create destroy] do
        collection do
          post :new_create_challenge
        end

        member do
          post :new_destroy_challenge
        end
      end
    end
  end
end
