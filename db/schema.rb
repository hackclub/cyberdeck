# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_21_130000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "participants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "eligibility_checked_at"
    t.text "email"
    t.string "first_name"
    t.string "github_login"
    t.text "github_refresh_token"
    t.text "github_token"
    t.datetime "github_token_expires_at"
    t.datetime "github_token_revoke_after"
    t.bigint "github_user_id"
    t.text "hackatime_api_key"
    t.text "hackatime_token"
    t.string "hackatime_trust_level"
    t.string "hackatime_user_id"
    t.string "hca_id", null: false
    t.text "hca_refresh_token"
    t.text "hca_token"
    t.string "last_name"
    t.boolean "shipped_before", default: false, null: false
    t.string "slack_id"
    t.datetime "updated_at", null: false
    t.string "verification_status"
    t.boolean "ysws_eligible", default: false, null: false
    t.index ["email"], name: "index_participants_on_email", unique: true
    t.index ["github_token_revoke_after"], name: "index_participants_on_github_token_to_revoke", where: "(github_token IS NOT NULL)"
    t.index ["hackatime_user_id"], name: "index_participants_on_hackatime_user_id"
    t.index ["hca_id"], name: "index_participants_on_hca_id", unique: true
  end

  create_table "program_repositories", force: :cascade do |t|
    t.datetime "claimed_at", null: false
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "full_name", null: false
    t.bigint "github_repo_id"
    t.bigint "participant_id", null: false
    t.bigint "project_id"
    t.bigint "provisioning_id"
    t.string "template_full_name"
    t.datetime "updated_at", null: false
    t.index ["github_repo_id"], name: "index_program_repositories_on_github_repo_id", unique: true
    t.index ["participant_id", "full_name"], name: "index_program_repositories_on_participant_id_and_full_name"
    t.index ["participant_id"], name: "index_program_repositories_on_participant_id"
    t.index ["project_id"], name: "index_program_repositories_on_project_id"
    t.index ["provisioning_id"], name: "index_program_repositories_on_provisioning_id"
  end

  create_table "projects", force: :cascade do |t|
    t.string "airtable_record_id"
    t.string "code_url"
    t.string "codespace_name"
    t.string "codespace_url"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "hackatime_project_name"
    t.string "kind", default: "codespace", null: false
    t.string "name", null: false
    t.bigint "participant_id", null: false
    t.string "playable_url"
    t.string "repo_full_name"
    t.bigint "repo_id"
    t.string "repo_name", null: false
    t.string "status", default: "setting_up", null: false
    t.datetime "submitted_at"
    t.datetime "updated_at", null: false
    t.index ["participant_id", "status"], name: "index_projects_on_participant_id_and_status"
    t.index ["participant_id"], name: "index_projects_on_participant_id"
    t.index ["repo_id"], name: "index_projects_on_repo_id", unique: true, where: "(repo_id IS NOT NULL)"
  end

  create_table "provisionings", force: :cascade do |t|
    t.string "codespace_name"
    t.string "codespace_url"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.bigint "participant_id", null: false
    t.bigint "project_id", null: false
    t.string "repo_full_name"
    t.bigint "repo_id"
    t.string "repo_name", null: false
    t.string "status", default: "pending", null: false
    t.string "step"
    t.datetime "updated_at", null: false
    t.index ["participant_id", "status"], name: "index_provisionings_on_participant_id_and_status"
    t.index ["participant_id"], name: "index_provisionings_on_participant_id"
    t.index ["participant_id"], name: "index_provisionings_one_in_progress_per_participant", unique: true, where: "((status)::text = ANY ((ARRAY['pending'::character varying, 'running'::character varying])::text[]))"
    t.index ["project_id"], name: "index_provisionings_on_project_id"
    t.index ["project_id"], name: "index_provisionings_one_live_per_project", unique: true, where: "((status)::text = ANY ((ARRAY['pending'::character varying, 'running'::character varying, 'completed'::character varying])::text[]))"
  end

  create_table "rsvps", force: :cascade do |t|
    t.string "airtable_record_id"
    t.string "country"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "ip"
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.string "utm_campaign"
    t.string "utm_content"
    t.string "utm_medium"
    t.string "utm_source"
    t.index ["email"], name: "index_rsvps_on_email", unique: true
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.bigint "channel_hash", null: false
    t.datetime "created_at", null: false
    t.binary "payload", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_batch_executions", force: :cascade do |t|
    t.bigint "batch_id", null: false
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.index ["batch_id"], name: "index_solid_queue_batch_executions_on_batch_id"
    t.index ["job_id"], name: "index_solid_queue_batch_executions_on_job_id", unique: true
  end

  create_table "solid_queue_batches", force: :cascade do |t|
    t.string "active_job_batch_id"
    t.integer "completed_jobs", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.datetime "enqueued_at"
    t.datetime "failed_at"
    t.integer "failed_jobs", default: 0, null: false
    t.datetime "finished_at"
    t.text "metadata"
    t.text "on_failure"
    t.text "on_finish"
    t.text "on_success"
    t.integer "total_jobs", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_batch_id"], name: "index_solid_queue_batches_on_active_job_batch_id", unique: true
    t.index ["finished_at"], name: "index_solid_queue_batches_on_finished_at"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.bigint "batch_id"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["batch_id"], name: "index_solid_queue_jobs_on_batch_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  add_foreign_key "program_repositories", "participants"
  add_foreign_key "program_repositories", "projects"
  add_foreign_key "program_repositories", "provisionings"
  add_foreign_key "projects", "participants"
  add_foreign_key "provisionings", "participants"
  add_foreign_key "provisionings", "projects"
  add_foreign_key "solid_queue_batch_executions", "solid_queue_batches", column: "batch_id", on_delete: :cascade
  add_foreign_key "solid_queue_batch_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
end
