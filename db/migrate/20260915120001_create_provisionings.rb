class CreateProvisionings < ActiveRecord::Migration[8.1]
  def change
    create_table :provisionings do |t|
      t.references :participant, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.string :step
      t.string :repo_name, null: false
      t.string :repo_full_name
      t.bigint :repo_id
      t.string :codespace_name
      t.string :codespace_url
      t.text     :error_message
      t.datetime :completed_at
      t.timestamps
    end

    add_index :provisionings, %i[participant_id status]
  end
end
