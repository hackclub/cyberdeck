# frozen_string_literal: true

# The hidden link, /early/<token>. A wrong token, or none set, is a plain 404
# so the route does not show that it exists. See D-030.
class EarlyAccessController < ApplicationController
  def show
    return head(:not_found) unless EarlyAccess.token?(params[:token])

    session[EarlyAccess::SESSION_KEY] = true
    redirect_to start_path
  end
end
