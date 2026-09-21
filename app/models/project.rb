# frozen_string_literal: true

# One participant build: the repository, the editor, and later the submission.
# A Provisioning is one attempt to set the project up. The project outlives
# every attempt, so a failed run or a deleted Codespace leaves the project
# standing and offers setup again.
#
# The submission columns mirror what the program base's YSWS Project Submission
# table asks for about the project itself. Nothing writes them yet.
# See wiki/decisions/D-019-projects.md.
class Project < ApplicationRecord
  belongs_to :participant
  has_many :provisionings, dependent: :destroy
  has_many :program_repositories, dependent: :nullify

  KINDS    = %w[codespace local].freeze
  STATUSES = %w[setting_up ready failed gone].freeze

  validates :kind,   inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :name, :repo_name, presence: true

  scope :latest,     -> { order(created_at: :desc, id: :desc) }
  scope :ready,      -> { where(status: "ready") }
  scope :setting_up, -> { where(status: "setting_up") }

  def codespace? = kind == "codespace"
  def local?     = kind == "local"

  def setting_up? = status == "setting_up"
  def ready?      = status == "ready"
  def failed?     = status == "failed"
  def gone?       = status == "gone"

  # A run can start when nothing is live. Gone and failed both qualify; a run
  # on a gone project builds a fresh repository and editor.
  def may_retry? = live_run.nil?

  # The steps a run for this kind of project goes through, in order. A local
  # project stops after the repository: the participant brings the editor.
  def steps = local? ? %w[repo] : Provisioning::STEPS

  # The run the project page describes. The live run when there is one: it
  # holds the repository and the editor. Otherwise the newest run, which
  # explains what went wrong. In normal use the live run is also the newest,
  # because nothing can start while one is live. The rows carried over on
  # 2026-09-18 are the exception: Armand's live run sits among later test runs.
  def current_run = live_run || provisionings.latest.first
  def live_run    = provisionings.live.latest.first

  def repo_url = repo_full_name.presence && "https://github.com/#{repo_full_name}"

  STATUS_FOR_RUN = {
    "pending" => "setting_up", "running" => "setting_up", "completed" => "ready",
    "failed" => "failed", "superseded" => "failed", "missing" => "gone"
  }.freeze

  # Called by a run whenever its state changes. Copies what the run has
  # learned onto the project, so the project is the one place to read it.
  # Only the current run may speak, or a run that was live until this save:
  # an older row being tidied must not overwrite what a later run built.
  def sync_from!(run)
    # A new row's "before" value is the column default, "pending", which is
    # live. Only an update can have been live.
    was_live = !run.previously_new_record? && Provisioning::LIVE.include?(run.status_before_last_save)
    return unless was_live || run.id == current_run&.id

    attrs = { status: STATUS_FOR_RUN.fetch(run.status), repo_name: run.repo_name }
    if run.repo_full_name.present?
      attrs[:repo_full_name] = run.repo_full_name
      attrs[:repo_id]        = run.repo_id
      attrs[:code_url]       = "https://github.com/#{run.repo_full_name}"
      attrs[:hackatime_project_name] = run.repo_name
    end
    if run.completed?
      attrs[:codespace_name] = run.codespace_name
      attrs[:codespace_url]  = run.codespace_url
    end
    update!(attrs)
  end
end
