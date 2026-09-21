# frozen_string_literal: true

# The public landing page at the root. It sells the program and has one
# action. While sign-ups are closed that is an RSVP email box, see
# RsvpsController. Once they open it is "Get started", which leads to the
# onboarding overview at /start. A participant who has already connected
# everything sees "Continue" instead.
class LandingController < ApplicationController
  def show
    @complete = signed_in? && current_participant.hackatime_api_key.present? &&
                current_participant.github_token.present?
  end
end
