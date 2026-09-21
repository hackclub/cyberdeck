# frozen_string_literal: true

# One row per email left in the landing page's RSVP box while sign-ups are
# closed, with where it came from: the address, the country Cloudflare saw,
# and the utm parameters on the landing page link. The row is a buffer:
# SyncRsvpJob copies it to the RSVP table of the program base and records the
# Airtable record id and when. See wiki/decisions/D-023 and D-025.
class CreateRsvps < ActiveRecord::Migration[8.1]
  def change
    create_table :rsvps do |t|
      t.string :email, null: false
      t.string :ip
      t.string :country
      t.string :utm_source
      t.string :utm_medium
      t.string :utm_campaign
      t.string :utm_content
      t.string :airtable_record_id
      t.datetime :synced_at
      t.timestamps
    end
    # The model lowercases before it saves, so a plain index is case-proof.
    add_index :rsvps, :email, unique: true
  end
end
