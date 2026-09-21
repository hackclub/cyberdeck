class CreateParticipants < ActiveRecord::Migration[8.1]
  def change
    create_table :participants do |t|
      t.string  :hca_id, null: false
      t.text    :email
      t.string  :first_name
      t.string  :last_name
      t.string  :slack_id
      t.string  :verification_status
      t.boolean :ysws_eligible, null: false, default: false
      t.datetime :eligibility_checked_at
      t.string  :hackatime_user_id
      t.string  :hackatime_trust_level
      t.string  :github_login
      t.bigint  :github_user_id
      t.datetime :github_token_expires_at
      t.boolean :shipped_before, null: false, default: false
      t.text :hca_token
      t.text :hca_refresh_token
      t.text :hackatime_token
      t.text :hackatime_api_key
      t.text :github_token
      t.text :github_refresh_token
      t.timestamps
    end

    add_index :participants, :hca_id, unique: true
    add_index :participants, :email, unique: true
    add_index :participants, :hackatime_user_id
  end
end
