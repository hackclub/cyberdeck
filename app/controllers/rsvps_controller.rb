# frozen_string_literal: true

# The RSVP box on the landing page. It takes one email, stores it, and sends
# the person on to the Fillout form. The email is kept whether or not they
# finish the form. Armand, 2026-09-21. Nothing is emailed from here.
#
# Shape follows hackclub/jamegam's /api/signup: a honeypot field that only
# bots fill, a per-address rate limit, and a repeat submit that reads as
# success rather than as an error. See D-023.
class RsvpsController < ApplicationController
  include LandingPage

  HONEYPOT = :company
  DONE     = "You’re in! We’ll email you when sign-ups open."
  INVALID  = "That doesn’t look like an email. Try again?"
  TOO_MANY = "Slow down a sec! Try again in a minute."

  rate_limit to: 5, within: 1.minute, only: :create,
             with: -> { redirect_to root_path(anchor: slot), alert: TOO_MANY, status: :see_other }

  def create
    # A filled honeypot is a bot. Say yes, keep nothing, send it nowhere.
    return done if params[HONEYPOT].present?

    # The hidden fields of the form are the only source. See D-029.
    rsvp = Rsvp.new(email: params[:email], ip: client_ip, country: country, **utm)
    return onward(rsvp.email) if rsvp.save

    # The same email twice is not an error. The row is already there.
    return onward(rsvp.email) if rsvp.errors.of_kind?(:email, :taken)

    # Render rather than redirect. A redirect drops the posted hidden fields,
    # and nothing on the device remembers them. See D-029.
    flash.now[:rsvp_error] = INVALID
    flash.now[:rsvp_email] = params[:email].to_s.first(Rsvp::MAX_EMAIL)
    render_landing(status: 422)
  end

  private

  # On to the Fillout form, with the email in its URL so the form's email
  # field is filled. Without a form URL, the box says thanks and stays.
  def onward(email)
    return done if fillout_url.blank?

    redirect_to fillout_url_for(email), status: :see_other, allow_other_host: true
  end

  def done
    flash[:rsvp_done] = DONE
    redirect_to root_path(anchor: slot), status: :see_other
  end

  def fillout_url = Rails.configuration.x.fillout_url

  # Cloudflare fronts cyberdeck.hackclub.com and adds the visitor's country
  # as a two-letter code. Absent anywhere else, so nil in development.
  # "XX" is Cloudflare's own value for an address it cannot place, and "T1"
  # is Tor. Neither is a country, so both are dropped.
  def country
    code = request.headers["CF-IPCountry"].presence&.first(2)&.upcase
    code if code && !%w[XX T1].include?(code)
  end

  # Cloudflare's own header holds the visitor's address and nothing else.
  # `remote_ip` reads X-Forwarded-For, which behind two proxies can end up
  # holding an infrastructure address instead. Prefer the header, fall back.
  def client_ip = request.headers["CF-Connecting-IP"].presence&.first(45) || request.remote_ip

  def fillout_url_for(email)
    uri = URI(fillout_url)
    query = URI.decode_www_form(uri.query.to_s).reject { |k, _| k == "email" }
    query << [ "email", email ]
    uri.query = URI.encode_www_form(query)
    uri.to_s
  end

  # Which of the two boxes was used, so the page lands back on it.
  def slot = params[:slot] == "rsvp-end" ? "rsvp-end" : "top"
end
