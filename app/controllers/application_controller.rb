# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include UtmCapture

  allow_browser versions: :modern

  helper_method :current_participant, :signed_in?, :signups_open?

  private

  # Closed unless SIGNUPS_OPEN=1. See config/application.rb.
  def signups_open? = Rails.configuration.x.signups_open

  # Every route into the login chain. While sign-ups are closed they all
  # land back on the landing page and its RSVP box.
  def require_signups_open!
    return if signups_open?

    redirect_to root_path, notice: "Sign-ups aren’t open yet! Leave your email and we’ll let you know."
  end

  # The session cookie holds a participant id and nothing else. Tokens live in
  # Postgres, encrypted. See wiki/concepts/app-security.md.
  def current_participant
    return @current_participant if defined?(@current_participant)

    @current_participant = Participant.find_by(id: session[:participant_id])
  end

  def signed_in? = current_participant.present?

  def require_participant!
    return if signed_in?

    redirect_to start_path, alert: "Start by signing in with Hack Club."
  end

  # Default-allow. Only an explicit ban from Hack Club Auth stops someone.
  # Identity verification is not required to take part.
  #
  # `performed?` is the check that matters: require_participant! may already
  # have issued a redirect, and reading current_participant after that would
  # raise on nil.
  def require_allowed!
    require_participant!
    return if performed?
    return if current_participant.may_participate?

    redirect_to root_path,
                alert: "This account cannot take part. If you think that is wrong, ask in the program channel."
  end
end
