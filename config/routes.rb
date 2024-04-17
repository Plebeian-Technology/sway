Rails.application.routes.draw do
  resources :user_invites
  resources :user_votes
  root "home#index"

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
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
