# frozen_string_literal: true

# A project is what the participant would call the thing: the repository, the
# editor, and later the submission. Before this, all of that hung off one
# provisioning attempt, and nothing outlived a failed or deleted run.
# See wiki/decisions/D-019-projects.md.
class CreateProjects < ActiveRecord::Migration[8.1]
  # Bare table classes, so the migration does not depend on the app's models
  # or their callbacks.
  class Run < ActiveRecord::Base
    self.table_name = "provisionings"
  end

  class Project < ActiveRecord::Base
    self.table_name = "projects"
  end

  LIVE = %w[pending running completed].freeze

  STATUS_FOR_RUN = {
    "pending" => "setting_up", "running" => "setting_up", "completed" => "ready",
    "failed" => "failed", "superseded" => "failed", "missing" => "gone"
  }.freeze

  def up
    create_table :projects do |t|
      t.references :participant, null: false, foreign_key: true
      t.string  :name,      null: false
      t.string  :kind,      null: false, default: "codespace"
      t.string  :status,    null: false, default: "setting_up"
      t.string  :repo_name, null: false
      t.string  :repo_full_name
      t.bigint  :repo_id
      t.string  :codespace_name
      t.string  :codespace_url
      # The fields the program base's YSWS Project Submission table asks for
      # about the project itself. Filled later, when the participant ships.
      t.text     :description
      t.string   :code_url
      t.string   :playable_url
      t.string   :hackatime_project_name
      t.string   :airtable_record_id
      t.datetime :submitted_at
      t.timestamps
    end
    add_index :projects, :repo_id, unique: true, where: "repo_id IS NOT NULL"
    add_index :projects, %i[participant_id status]

    add_reference :provisionings,        :project, foreign_key: true
    add_reference :program_repositories, :project, foreign_key: true

    # Every existing run belongs to one project per participant, built from
    # their latest live run, or their latest run of any kind. Nothing is
    # deleted: the app never deletes, Armand, 2026-09-17.
    Run.distinct.pluck(:participant_id).each do |participant_id|
      runs   = Run.where(participant_id: participant_id).order(:created_at)
      anchor = runs.where(status: LIVE).order(created_at: :desc).first || runs.last
      done   = anchor.status == "completed"

      project = Project.create!(
        participant_id: participant_id,
        name:           anchor.repo_name,
        kind:           "codespace",
        status:         STATUS_FOR_RUN.fetch(anchor.status),
        repo_name:      anchor.repo_name,
        repo_full_name: anchor.repo_full_name,
        repo_id:        anchor.repo_id,
        codespace_name: (anchor.codespace_name if done),
        codespace_url:  (anchor.codespace_url if done),
        code_url:       (anchor.repo_full_name && "https://github.com/#{anchor.repo_full_name}"),
        hackatime_project_name: anchor.repo_name,
        created_at:     runs.first.created_at,
        updated_at:     Time.current
      )
      runs.update_all(project_id: project.id)
      execute "UPDATE program_repositories SET project_id = #{project.id} WHERE participant_id = #{participant_id}"
    end

    change_column_null :provisionings, :project_id, false

    # One live run per project, so a retry cannot double up. One run in
    # progress per participant, so two projects cannot provision at once.
    remove_index :provisionings, name: "index_provisionings_one_live_per_participant"
    add_index :provisionings, :project_id, unique: true,
              where: "status IN ('pending', 'running', 'completed')",
              name: "index_provisionings_one_live_per_project"
    add_index :provisionings, :participant_id, unique: true,
              where: "status IN ('pending', 'running')",
              name: "index_provisionings_one_in_progress_per_participant"
  end

  def down
    remove_index :provisionings, name: "index_provisionings_one_in_progress_per_participant"
    remove_index :provisionings, name: "index_provisionings_one_live_per_project"
    add_index :provisionings, :participant_id, unique: true,
              where: "status IN ('pending', 'running', 'completed')",
              name: "index_provisionings_one_live_per_participant"
    remove_reference :program_repositories, :project, foreign_key: true
    remove_reference :provisionings,        :project, foreign_key: true
    drop_table :projects
  end
end
