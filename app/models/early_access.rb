# frozen_string_literal: true

# The way past closed sign-ups for Hack Club email addresses. A link that no
# page shows sets a flag in the session. Hack Club Auth must then return an
# address that ends in @hackclub.com. The address is the gate and the link
# only hides the way in. See wiki/decisions/D-030-hidden-hack-club-email-login.md.
module EarlyAccess
  DOMAIN = "@hackclub.com"
  SESSION_KEY = "early_access"

  # True when the token is set in the environment and the given one matches.
  def self.token?(given)
    expected = ENV["EARLY_ACCESS_TOKEN"].to_s
    return false if expected.length < 16 || given.blank?

    ActiveSupport::SecurityUtils.secure_compare(given.to_s, expected)
  end

  def self.email?(email)
    email.to_s.strip.downcase.end_with?(DOMAIN)
  end

  # A Rack or Rails session. Open for the browser that used the link, or for
  # a participant who already signed in with a Hack Club address.
  def self.session?(session)
    return false if session.nil?
    return true if session[SESSION_KEY] == true

    participant = Participant.find_by(id: session[:participant_id])
    participant.present? && email?(participant.email)
  end
end
