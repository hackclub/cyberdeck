# frozen_string_literal: true

# An email left on the landing page while sign-ups are closed, plus where it
# came from: the request's address, the country Cloudflare saw, and the utm
# parameters on the link. Nothing else is known about the person. Each row
# is copied to the RSVP table of the program base by SyncRsvpJob as soon as
# it exists.
# See wiki/decisions/D-023-rsvp-to-airtable-fillout-prefill.md.
class Rsvp < ApplicationRecord
  MAX_EMAIL = 254
  UTM = %w[utm_source utm_medium utm_campaign utm_content].freeze

  # The fields the Airtable row gets, by Airtable field name.
  def airtable_fields
    { "Email" => email, "IP" => ip, "Country" => country,
      "utm_source" => utm_source, "utm_medium" => utm_medium,
      "utm_campaign" => utm_campaign, "utm_content" => utm_content }.compact
  end

  before_validation { self.email = email.to_s.strip.downcase }

  validates :email, presence: true, length: { maximum: MAX_EMAIL },
                    format: { with: URI::MailTo::EMAIL_REGEXP },
                    uniqueness: true

  after_create_commit { SyncRsvpJob.perform_later(id) }

  def synced? = synced_at.present?
end
