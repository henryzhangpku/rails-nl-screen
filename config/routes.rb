Rails.application.routes.draw do
  resources :screens, only: %i[index new create show destroy]
  root "screens#new"

  # Health check for load balancers / Kamal.
  get "up" => "rails/health#show", as: :rails_health_check
end
