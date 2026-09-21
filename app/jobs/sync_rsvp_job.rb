# frozen_string_literal: true

# Copies one RSVP row to the RSVP table of the program base, right after it
# is created. One job per row: the volume is one email per click, so the
# rolling batch job of D-020 is not needed here. Merges on Email, so a retry
# never doubles a row. Armand, 2026-09-21: the email "should go into a rsvp
# table in airtable". See wiki/decisions/D-023-rsvp-to-airtable-fillout-prefill.md.
class SyncRsvpJob < ApplicationJob
  TABLE = "RSVP"

  queue_as :default
  # How the job gets its client. Tests swap in a fake.
  class_attribute :client_factory, default: -> { AirtableClient.new }
  # Airtable answers 429 with a 30 second penalty, and it has outages. Wait
  # them out rather than drop the email.
  retry_on AirtableClient::Error, wait: :polynomially_longer, attempts: 8
  discard_on ActiveRecord::RecordNotFound

  def perform(rsvp_id)
    rsvp = Rsvp.find(rsvp_id)
    return if rsvp.synced?

    record_id = client_factory.call.upsert(TABLE, rsvp.airtable_fields, merge_on: [ "Email" ])
    rsvp.update!(airtable_record_id: record_id, synced_at: Time.current)
  end
end
