class OneLiveProvisioningPerParticipant < ActiveRecord::Migration[8.1]
  def change
    # A participant gets one provisioning that is pending, running or done.
    # Enforced here rather than only in the controller, so a double-click, a
    # stale form or two requests racing cannot produce a second repository and
    # a second Codespace. Failed and superseded runs are excluded, which is
    # what keeps retrying possible.
    add_index :provisionings, :participant_id,
              unique: true,
              where: "status IN ('pending', 'running', 'completed')",
              name: "index_provisionings_one_live_per_participant"
  end
end
