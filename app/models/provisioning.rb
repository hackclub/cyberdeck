# frozen_string_literal: true

# One attempt to turn a project into a repository and, for a Codespace project,
# a working Codespace. Kept as a record rather than a bare job so the project
# page has something to poll, and so a failure leaves an explanation behind.
class Provisioning < ApplicationRecord
  belongs_to :participant
  belongs_to :project
  has_many :program_repositories, dependent: :nullify

  STATUSES = %w[pending running completed failed superseded missing].freeze
  STEPS    = %w[repo secret codespace].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :repo_name, presence: true

  scope :latest, -> { order(created_at: :desc, id: :desc) }

  # The project is the one place the app reads state from, so every change
  # here is copied up. See Project#sync_from!. A new run counts even when its
  # status equals the column default, which is not a recorded change.
  after_create :sync_project
  after_update :sync_project, if: lambda {
    saved_change_to_status? || saved_change_to_repo_full_name? || saved_change_to_codespace_url?
  }

  def step!(name)
    update!(status: "running", step: name.to_s)
  end

  def complete!
    update!(status: "completed", step: nil, completed_at: Time.current)
  end

  # The message reaches the participant, so it says what happened and what to
  # do about it, never an internal error string.
  def fail!(message)
    update!(status: "failed", error_message: message)
  end

  # What VerifyProvisioningsJob records when GitHub no longer has the thing
  # this run created. Not a failure: the setup worked, and then it was deleted.
  # Leaving LIVE is the point, because it lets the participant start again.
  def mark_missing!(message)
    update!(status: "missing", error_message: message)
  end

  def running?    = status == "running"
  def completed?  = status == "completed"
  def failed?     = status == "failed"
  def superseded? = status == "superseded"
  # The repository or Codespace this run produced no longer exists on GitHub.
  def missing?    = status == "missing"

  # Statuses the job can still move. Anything else is final, so the project
  # page must stop polling.
  IN_PROGRESS = %w[pending running].freeze
  def in_progress? = IN_PROGRESS.include?(status)

  # Statuses that still hold a repository and a Codespace, so a project must
  # not start another run while one exists.
  LIVE = %w[pending running completed].freeze
  scope :live, -> { where(status: LIVE) }

  private

  def sync_project = project.sync_from!(self)
end
