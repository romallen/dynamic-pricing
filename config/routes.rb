Rails.application.routes.draw do
  # Liveness probe — returns 200 if the app has booted. Used by load balancers
  # and uptime checks. Provided by Rails' built-in health controller.
  get "up", to: "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      get "/pricing", to: "pricing#index"
    end
  end
end
