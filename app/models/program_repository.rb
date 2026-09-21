# frozen_string_literal: true

# Proof that this program created a particular GitHub repository.
#
# Without it there is no safe way to tell a repository we made from one the
# participant made themselves. That matters: the provisioning job writes a
# Codespaces secret into the repository and opens a Codespace in it, and
# neither is a reasonable thing to do to somebody's unrelated project.
#
# A row is claimed before the repository is asked for and confirmed after, so
# a crash in between still leaves a trace rather than an orphan.
class ProgramRepository < ApplicationRecord
  belongs_to :participant
  belongs_to :project, optional: true
  belongs_to :provisioning, optional: true

  validates :full_name, presence: true

  scope :confirmed, -> { where.not(github_repo_id: nil) }

  def self.claim!(participant:, provisioning:, full_name:, template:)
    create!(participant: participant, provisioning: provisioning,
            project: provisioning.project,
            full_name: full_name, template_full_name: template,
            claimed_at: Time.current)
  end

  def confirm!(repo)
    update!(github_repo_id: repo["id"], full_name: repo["full_name"],
            confirmed_at: Time.current)
  end

  # Did this program create the repository GitHub is describing?
  def self.created_by_program?(participant:, repo:)
    confirmed.exists?(participant: participant, github_repo_id: repo["id"])
  end
end
