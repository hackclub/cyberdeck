# frozen_string_literal: true

# A short link. It writes the utm cookie and sends the person to the home
# page, so the address bar ends at cyberdeck.hackclub.com with nothing after
# it. An unknown code goes to the home page too, rather than a 404, because
# a mistyped link should still reach the program.
class LinksController < ApplicationController
  def show
    utm = ShortLink.utm_for(params[:code])
    store_utm(utm) if utm.present?

    redirect_to root_path, status: :see_other
  end
end
