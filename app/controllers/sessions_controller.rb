# frozen_string_literal: true

# One callback for all three providers. Each writes what it knows onto the
# participant row and hands off to the next step.
# See wiki/concepts/one-click-login.md for the chain.
class SessionsController < ApplicationController
  skip_forgery_protection only: :failure

  def create
    case auth.provider
    when "hack_club" then sign_in_with_hack_club
    when "hackatime" then link_hackatime
    when "github"    then link_github
    else redirect_to start_path, alert: "Unknown sign-in provider."
    end
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "Signed out."
  end

  # A declined or failed grant sends the participant back to that step's own
  # screen, which then explains why the step cannot be skipped.
  def failure
    # The request phase refused because sign-ups are closed. See the
    # OmniAuth initializer.
    return require_signups_open! unless signups_open?

    provider = params[:strategy].presence || request.env.dig("omniauth.error.strategy")&.name
    if provider.present? && OnboardingController::STEPS.any? { |s| s[:key] == provider.to_s }
      redirect_to connect_path(provider: provider, declined: 1)
    else
      redirect_to start_path, alert: "Sign-in did not finish. Start again below."
    end
  end

  private

  def auth = request.env["omniauth.auth"]

  # Step 1. Identity, and the only check on whether they may take part.
  def sign_in_with_hack_club
    info = auth.info
    raw  = auth.extra&.raw_info || {}

    # While sign-ups are closed only a Hack Club address gets in. Checked
    # before anything is saved. See D-030.
    unless Rails.configuration.x.signups_open || EarlyAccess.email?(info.email)
      reset_session
      return redirect_to root_path, notice: "Sign-ups aren’t open yet! Leave your email and we’ll let you know."
    end

    participant = Participant.find_or_initialize_by(hca_id: auth.uid)
    participant.assign_attributes(
      email: info.email,
      first_name: info.first_name || raw["first_name"],
      last_name: info.last_name || raw["last_name"],
      slack_id: info.slack_id || raw["slack_id"],
      verification_status: raw["verification_status"],
      ysws_eligible: !!raw["ysws_eligible"],
      eligibility_checked_at: Time.current,
      hca_token: auth.credentials&.token,
      hca_refresh_token: auth.credentials&.refresh_token
    )
    participant.save!

    reset_session
    session[:participant_id] = participant.id

    if participant.blocked?
      # They cannot take part, so we have no reason to keep a token that can
      # write to their repositories.
      participant.revoke_github_token!
      return redirect_to root_path, alert: blocked_message
    end

    # Back to the onboarding, which shows the next step's explanation screen.
    redirect_to onboarding_next_path(from: "hack_club")
  end

  # Step 2. The Hackatime API key, and the token hours are read with later.
  def link_hackatime
    return redirect_to(start_path, alert: "Sign in with Hack Club first.") unless signed_in?

    participant = current_participant
    participant.update!(
      hackatime_user_id: auth.uid,
      hackatime_trust_level: auth.extra&.trust_level,
      hackatime_token: auth.credentials&.token,
      hackatime_api_key: auth.extra&.api_key,
      github_login: participant.github_login.presence || auth.info&.github_username
    )

    if participant.hackatime_banned?
      return redirect_to root_path,
                         alert: "Hackatime has this account marked as banned, so it cannot take part."
    end

    if participant.hackatime_api_key.blank?
      return redirect_to start_path,
                         alert: "Hackatime did not return an API key. Try again, or ask in the program channel."
    end

    redirect_to onboarding_next_path(from: "hackatime")
  end

  # Step 3. GitHub, held for about a minute. See D-013.
  def link_github
    return redirect_to(start_path, alert: "Sign in with Hack Club first.") unless signed_in?

    current_participant.update!(
      github_login: auth.info&.nickname,
      github_user_id: auth.uid,
      github_token: auth.credentials&.token,
      github_refresh_token: auth.credentials&.refresh_token,
      github_token_expires_at: (Time.at(auth.credentials.expires_at) if auth.credentials&.expires_at)
    )

    # A participant who is here with a finished run usually lost the old
    # token: VerifyProvisioningsJob discards it on 401. Check that run again
    # with the new token now, so a deleted repository frees setup at once
    # rather than at the next hourly pass.
    current_participant.provisionings.where(status: "completed").find_each do |provisioning|
      VerifyProvisioningsJob.perform_later(provisioning.id)
    end

    redirect_to onboarding_next_path(from: "github")
  end

  # Where the participant goes after a callback: the next screen that still
  # has something to explain, or the finish line.
  # `from` names the grant that just completed, so the next screen can show it
  # ticking over rather than appearing already done. Cosmetic only: the real
  # state always comes from the participant record.
  def onboarding_next_path(from: nil)
    return connect_path(provider: "hack_club") unless signed_in?

    p = current_participant
    return connect_path(provider: "hackatime", from: from) if p.hackatime_api_key.blank?
    return connect_path(provider: "github", from: from)    if p.github_token.blank?

    done_path(from: from)
  end

  def blocked_message
    "This account cannot take part. If you think that is wrong, ask in the program channel."
  end
end
