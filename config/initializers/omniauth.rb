# frozen_string_literal: true

require Rails.root.join("lib/omniauth/strategies/hackatime")

# The request phase must be a POST from a form carrying a CSRF token.
# omniauth-rails_csrf_protection enforces it. A GET request phase lets any
# site start a login against this app.
OmniAuth.config.allowed_request_methods = %i[post]
OmniAuth.config.silence_get_warning = true

# Never let a provider's error text reach the participant verbatim.
OmniAuth.config.on_failure = proc { |env| SessionsController.action(:failure).call(env) }

# While sign-ups are closed, no request phase starts. A hand-made POST to
# /auth/:provider fails here, before any redirect to a provider, and lands in
# SessionsController#failure, which sends it to the landing page. The
# onboarding screens that hold the real buttons are gated separately.
# omniauth-rails_csrf_protection uses request_validation_phase, so this hook
# is free. A browser that used the hidden link passes. See D-022 and D-030.
OmniAuth.config.before_request_phase = proc { |env|
  open_for_all = Rails.configuration.x.signups_open
  unless open_for_all || EarlyAccess.session?(env["rack.session"])
    raise OmniAuth::Error, "Sign-ups are closed"
  end
}

creds = Rails.application.credentials

Rails.application.config.middleware.use OmniAuth::Builder do
  # 1. Identity and eligibility. The only authority on whether someone may
  #    take part. See wiki/concepts/hack-club-auth.md.
  provider :hack_club,
           creds.dig(:hack_club, :client_id),
           creds.dig(:hack_club, :client_secret),
           scope: "openid email name slack_id verification_status"

  # 2. The Hackatime API key the editor extension needs, plus the token that
  #    lets hours be checked at review time. See wiki/concepts/token-custody.md.
  provider :hackatime,
           creds.dig(:hackatime, :client_id),
           creds.dig(:hackatime, :client_secret),
           scope: "profile read"

  # 3. GitHub, for about one minute. The token is revoked when provisioning
  #    ends. See wiki/decisions/D-013-oauth-app-with-revoke.md.
  provider :github,
           creds.dig(:github, :client_id),
           creds.dig(:github, :client_secret),
           scope: "read:user user:email public_repo codespace"
end
