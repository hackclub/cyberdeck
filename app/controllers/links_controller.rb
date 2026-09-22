# frozen_string_literal: true

# A short link. It renders the landing page with the code's utm values in the
# RSVP form, and a Stimulus controller rewrites the address bar to the site
# root. So the page reads cyberdeck.hackclub.com with nothing after it, and a
# copied link carries no attribution.
#
# It renders rather than redirects because nothing is stored on the device any
# more. The form is the only carrier. See D-027 and D-029.
#
# An unknown code renders the same page rather than a 404, because a mistyped
# link should still reach the program.
class LinksController < ApplicationController
  include LandingPage

  def show
    store_utm(ShortLink.utm_for(params[:code]))
    render_landing
  end
end
