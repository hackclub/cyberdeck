class CreateProgramRepositories < ActiveRecord::Migration[8.1]
  def change
    create_table :program_repositories do |t|
      t.references :participant, null: false, foreign_key: true
      t.references :provisioning, foreign_key: true

      # Written BEFORE the repository is created, so a crash between the API
      # call and the response still leaves proof that we asked for this name.
      t.string   :full_name, null: false
      t.datetime :claimed_at, null: false

      # Filled in once GitHub answers. A row with a github_repo_id is a
      # repository this program definitely made.
      t.bigint   :github_repo_id
      t.datetime :confirmed_at

      # Which template it came from, so a later template change is traceable.
      t.string :template_full_name

      t.timestamps
    end

    add_index :program_repositories, :github_repo_id, unique: true
    add_index :program_repositories, %i[participant_id full_name]
  end
end
