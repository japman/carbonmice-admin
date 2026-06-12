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

  get "pricing_tiers", to: "pricing_tiers#index", as: :pricing_tiers
  get "pricing_tiers/event/:id/edit", to: "pricing_tiers#edit_event", as: :edit_event_pricing_tier
  patch "pricing_tiers/event/:id", to: "pricing_tiers#update_event", as: :event_pricing_tier
  get "pricing_tiers/offset/:id/edit", to: "pricing_tiers#edit_offset", as: :edit_offset_pricing_tier
  patch "pricing_tiers/offset/:id", to: "pricing_tiers#update_offset", as: :offset_pricing_tier

  resources :categories, only: %i[index edit update]
  resource :password, only: %i[edit update]
end
