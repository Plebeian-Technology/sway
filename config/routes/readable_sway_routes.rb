Rails.application.routes.draw do
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

  namespace "admin" do
    resources :bills, only: %i[create update]
    resources :bill_of_the_week_schedule, only: %i[update]
    # resources :legislator_votes, only: %i[create]
    # resources :organizations, only: %i[create]
    # resources :organization_bill_positions, only: %i[create]
  end
end
