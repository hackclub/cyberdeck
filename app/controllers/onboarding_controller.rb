# frozen_string_literal: true

# The multi-screen onboarding. Every OAuth grant gets its own screen first,
# explaining what is about to be asked for and why, so nobody is dropped onto
# a consent screen with no context.
#
# There is no skip. All three grants are needed for the program to work, so
# the screens say so rather than offering a way around them.
class OnboardingController < ApplicationController
  before_action :require_signups_open!

  STEPS = [
    { key: "hack_club", label: "Hack Club" },
    { key: "hackatime", label: "Hackatime" },
    { key: "github",    label: "GitHub" }
  ].freeze

  # Hack Club Auth comes first because it creates the participant record that
  # the other two attach to. Hackatime and GitHub can be done in either order.
  FIRST = "hack_club"

  # The overview at /start. Shown whether this is a first visit or a return
  # partway through. Someone coming back should see where they got to
  # and choose what to do next, not be dropped into a half-finished step.
  def intro
    # Nothing left to connect: the overview has nothing to say, so go to the
    # finish line. Deliberately NOT straight to a running setup: landing on a
    # progress screen you did not ask for reads as something going wrong.
    # The finish line links to a run in progress instead.
    return redirect_to(done_path) if complete?

    @steps     = STEPS
    @done_keys = done_keys
    @next_key  = next_key
    @returning = signed_in? && @done_keys.any?
  end

  # One screen per grant.
  def connect
    @step_key = params[:provider]
    return redirect_to(start_path) unless STEPS.any? { |s| s[:key] == @step_key }
    return redirect_to(done_path) if done_keys.include?(@step_key)

    # The only ordering rule: the identity has to exist before anything can
    # attach to it.
    unless signed_in? || @step_key == FIRST
      return redirect_to connect_path(provider: FIRST, needs_first: @step_key)
    end

    @steps       = STEPS
    @done_keys   = done_keys
    # The grant that completed a moment ago, so the progress bar can show it
    # ticking over instead of appearing already done.
    @just_done   = params[:from].presence_in(STEPS.map { |s| s[:key] })
    @declined    = params[:declined].present?
    @needs_first = params[:needs_first].presence
    render @step_key
  end

  # The finish line, with the two ways to build. Once a project exists this
  # page has nothing to offer: the projects page shows the project's state,
  # and it is where a second project starts. See D-019.
  def done
    return redirect_to(start_path) unless complete?
    return redirect_to(projects_path) if current_participant.projects.exists?

    @participant = current_participant
    @steps       = STEPS
    @done_keys   = STEPS.map { |s| s[:key] }
    @just_done   = params[:from].presence_in(STEPS.map { |s| s[:key] })
  end

  private

  # Which grants are already in place.
  def done_keys
    return [] unless signed_in?

    keys = [ FIRST ]
    keys << "hackatime" if current_participant.hackatime_api_key.present?
    keys << "github"    if current_participant.github_token.present?
    keys
  end
  helper_method :done_keys

  # The first grant still missing, used for the Continue button.
  def next_key
    STEPS.map { |s| s[:key] }.find { |k| !done_keys.include?(k) }
  end

  def complete? = signed_in? && next_key.nil?
end
