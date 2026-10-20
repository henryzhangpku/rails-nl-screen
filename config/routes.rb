Rails.application.routes.draw do
  resource :session, only: %i[new create destroy]
  resources :screens, only: %i[index new create show destroy]
  root "screens#new"

  # PromptEngine's admin (where the LLM parser's prompt is edited and versioned)
  # is only routed for signed-in users; everyone else is sent to the sign-in page.
  # Its controllers also require the sign-in themselves (config/initializers/prompt_engine.rb).
  constraints ->(request) { Session.active.exists?(id: request.cookie_jar.signed[:session_id]) } do
    mount PromptEngine::Engine => "/prompts", as: :prompt_engine
  end
  get "prompts(/*path)", to: redirect("/session/new", status: 302)

  # Health check for load balancers / Kamal.
  get "up" => "rails/health#show", as: :rails_health_check
end
