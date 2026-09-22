# frozen_string_literal: true

# The landing page is rendered from three places. LandingController at the
# root, LinksController for a short code, and RsvpsController when an email
# is refused. All three need the same state, so it lives here.
module LandingPage
  extend ActiveSupport::Concern

  private

  def render_landing(status: :ok)
    @complete = signed_in? && current_participant.hackatime_api_key.present? &&
                current_participant.github_token.present?
    render template: "landing/show", status: status
  end
end
