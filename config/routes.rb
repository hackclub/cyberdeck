Rails.application.routes.draw do
  # The public landing page. The onboarding overview that used to sit here
  # moved to /start, which is where "Get started" points.
  root "landing#show"
  # The RSVP box on the landing page, while sign-ups are closed. See
  # wiki/decisions/D-022-signups-closed-rsvp.md.
  post "/rsvp", to: "rsvps#create", as: :rsvp
  get "/start", to: "onboarding#intro", as: :start

  # One screen per OAuth grant, shown before the participant is sent anywhere.
  get "/connect/:provider", to: "onboarding#connect", as: :connect
  # The finish line. Shown only until the first project exists; after that it
  # sends the participant to their projects.
  get "/done",              to: "onboarding#done",    as: :done

  # OmniAuth. The request phase is POST only, enforced in the initializer and
  # by omniauth-rails_csrf_protection.
  get  "/auth/:provider/callback", to: "sessions#create"
  post "/auth/:provider/callback", to: "sessions#create"
  get  "/auth/failure",            to: "sessions#failure"
  delete "/logout",                to: "sessions#destroy", as: :logout

  # A participant's projects. Creating one starts its first provisioning run.
  # A run can be started again on a project whose last run failed or whose
  # repository or Codespace is gone. See wiki/decisions/D-019-projects.md.
  resources :projects, only: %i[index show create] do
    resources :provisionings, only: :create
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
