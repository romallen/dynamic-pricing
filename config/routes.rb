Rails.application.routes.draw do
  get "up", to: "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      get "/pricing", to: "pricing#index"
    end
  end
end
