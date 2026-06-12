Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#show"
  resource :session, only: %i[new create destroy]
  resources :admin_users, only: %i[index new create edit update]
  resources :audit_logs, only: :index
  resources :events, only: %i[index show edit update] do
    member { patch :status }
  end
  resources :app_users, only: %i[index edit update]
  resources :emission_factors, only: %i[index new create edit update destroy]
end
