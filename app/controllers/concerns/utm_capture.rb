# frozen_string_literal: true

# The utm parameters on the link someone followed.
#
# They arrive in the address bar and would live only there: the landing page
# would read them on each request and nothing would remember them. A person
# who mistyped their email lost the attribution, because the error redirect
# carries no query string.
#
# So the first request that carries them writes them to a signed cookie for
# 90 days. Everything downstream reads the cookie. That survives a cleaned
# address bar, a typo, a browser restart, and a visit that returns days
# later. utm_controller.js strips the keys from the address bar once the
# server has them. See wiki/decisions/D-026-durable-utm.md.
module UtmCapture
  extend ActiveSupport::Concern

  COOKIE = :utm
  TTL    = 90.days
  # The most recent link wins. The one they followed last is the one that
  # brought them to the box.
  OVERWRITE = true

  included do
    before_action :capture_utm
    helper_method :utm, :utm_in_url?
  end

  private

  def capture_utm
    return if utm_from_url.empty?

    store_utm(utm_from_url)
  end

  # Also called by LinksController, which gets its values from a short code
  # rather than the address bar.
  def store_utm(values)
    return if values.blank?
    return if !OVERWRITE && utm_from_cookie.any?

    cookies.signed[COOKIE] = {
      value: values.to_json, expires: TTL.from_now,
      httponly: true, same_site: :lax, secure: request.ssl?
    }
    @utm = values
  end

  # What the RSVP row is stamped with. The cookie, or the address bar on the
  # very request that set the cookie.
  def utm = @utm ||= utm_from_cookie

  # True when this request's address bar still holds them, so the page knows
  # to strip them.
  def utm_in_url? = utm_from_url.any?

  def utm_from_url
    @utm_from_url ||= params.permit(*Rsvp::UTM).to_h
                            .transform_values { |v| v.to_s.first(200) }.compact_blank
  end

  def utm_from_cookie
    raw = cookies.signed[COOKIE]
    return {} if raw.blank?

    JSON.parse(raw).slice(*Rsvp::UTM).transform_values { |v| v.to_s.first(200) }.compact_blank
  rescue JSON::ParserError
    {}
  end
end
