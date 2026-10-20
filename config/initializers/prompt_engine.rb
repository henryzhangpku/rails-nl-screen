# PromptEngine's admin requires the same sign-in as the rest of the app, in the engine's
# own controller, so it stays closed even if the route constraint in config/routes.rb is
# removed or bypassed. The engine runs this hook each time its ApplicationController
# loads, so it also survives code reloading in development.
ActiveSupport.on_load(:prompt_engine_application_controller) do
  include Authentication
end
