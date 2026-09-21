# frozen_string_literal: true

# Kills GitHub tokens whose grace period is over.
#
# A provisioning run holds the participant's token for
# Participant::TOKEN_GRACE after it finishes, so a failed setup can be retried
# without reconnecting GitHub. This job is what ends that hold.
#
# Written as a sweeper over a query rather than one job per participant on a
# delay, because a delayed job is lost whenever the queue is (the async adapter
# in development loses everything on restart), and a lost job here means a live
# credential kept forever. Run it on a schedule; it is safe to run at any time
# and does nothing when no token is due.
class RevokeGithubTokenJob < ApplicationJob
  queue_as :default

  def perform(participant_id = nil)
    scope = Participant.github_token_due_for_revoke
    scope = scope.where(id: participant_id) if participant_id

    scope.find_each do |participant|
      participant.revoke_github_token!
      Rails.logger.info("RevokeGithubTokenJob: revoked participant #{participant.id}")
    end
  end
end
