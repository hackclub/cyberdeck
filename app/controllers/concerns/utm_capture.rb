# frozen_string_literal: true

# The utm parameters on the link someone followed.
#
# They ride in the request and nowhere else. A page that carries them renders
# them into the RSVP form as hidden fields, and the post brings them back. A
# short link supplies the same four values from its code. A refused email
# renders the page again rather than redirecting, so the fields survive.
#
# Nothing is written to the visitor's device. ePrivacy Art 5(3), which the UK
# implements as PECR, needs consent to store anything there unless the storage
# is strictly necessary for a service the visitor asked for. Attribution is
# not. See wiki/decisions/D-029-attribution-without-a-cookie.md, which
# supersedes the 90 day cookie of D-026.
module UtmCapture
  extend ActiveSupport::Concern

  # The cookie D-026 wrote. Any copy still on a device is expired on the next
  # request, so no stale attribution outlives the change.
  LEGACY_COOKIE = :utm

  included do
    before_action :drop_legacy_utm_cookie
    helper_method :utm, :normalize_address?
  end

  private

  def drop_legacy_utm_cookie
    cookies.delete(LEGACY_COOKIE) if cookies[LEGACY_COOKIE].present?
  end

  # What this request carries: the address bar on a landing, the hidden fields
  # on a post, or the values a short code stood for.
  def utm = @utm ||= utm_from_params

  # Called by LinksController, whose values come from a code rather than the
  # address bar.
  def store_utm(values) = @utm = values.presence || {}

  def utm_from_params
    params.permit(*Rsvp::UTM).to_h
          .transform_values { |v| v.to_s.first(200) }.compact_blank
  end

  # True when the page should rewrite the address bar to the site root: a utm
  # query string to take out, or a path such as /k3 or /rsvp to tidy away. A
  # copied link then carries no attribution.
  def normalize_address? = utm_from_params.any? || request.path != "/"
end
