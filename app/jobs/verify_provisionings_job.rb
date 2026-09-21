# frozen_string_literal: true

# Checks that what a completed run produced still exists on GitHub.
#
# Participants delete their own repositories and Codespaces, and nothing tells
# us when they do. Without this the app keeps offering an "Open my Codespace"
# button that 404s, and the one-live-run guard keeps refusing to build a
# replacement because it still believes one exists.
#
# A run whose repository or Codespace has gone is marked "missing", which is
# outside Provisioning::LIVE, so the participant is offered setup again.
class VerifyProvisioningsJob < ApplicationJob
  queue_as :default

  # Long enough that a run which finished moments ago is never judged on
  # GitHub's eventual consistency.
  SETTLE = 5.minutes

  def perform(provisioning_id = nil)
    scope = Provisioning.where(status: "completed").where(updated_at: ..SETTLE.ago)
    scope = scope.where(id: provisioning_id) if provisioning_id

    scope.includes(:participant).find_each { |provisioning| verify(provisioning) }
  end

  private

  def verify(provisioning)
    participant = provisioning.participant
    token = participant.github_token
    # Nothing to check with. Leave the run alone rather than guess.
    return if token.blank?

    client = GithubClient.new(token)

    if provisioning.repo_full_name.present? && client.repo(provisioning.repo_full_name).nil?
      # Deleting a repository takes its Codespaces with it, so this covers both.
      return mark(provisioning, "repository", "Your project repository is gone from GitHub. " \
                                              "Start setup again and we will build a new one.")
    end

    if provisioning.codespace_name.present? && client.codespace(provisioning.codespace_name).nil?
      mark(provisioning, "codespace", "Your editor was deleted on GitHub. " \
                                      "Start setup again and we will open a new one.")
    end
  rescue GithubClient::Error => e
    # 401 means GitHub no longer honours the token, so nothing about this run
    # can be checked until the participant connects GitHub again. Drop the
    # token: the app then asks them to reconnect, and SessionsController
    # re-runs this job for the run with the new token. Seen on 2026-09-17,
    # when a deleted repository sat behind a dead token and setup was never
    # offered again.
    if e.status == 401
      Rails.logger.warn("VerifyProvisioningsJob: ##{provisioning.id} token refused, discarding it")
      participant.discard_github_token!
      return
    end
    # A blip. Not evidence that anything was deleted.
    Rails.logger.warn("VerifyProvisioningsJob: skipped ##{provisioning.id}: #{e.message}")
  end

  def mark(provisioning, what, message)
    Rails.logger.info("VerifyProvisioningsJob: ##{provisioning.id} #{what} gone, marking missing")
    provisioning.mark_missing!(message)
  end
end
