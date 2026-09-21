class AddGithubTokenRevokeAfterToParticipants < ActiveRecord::Migration[8.1]
  def change
    add_column :participants, :github_token_revoke_after, :datetime
    # The sweeper looks up exactly this: tokens still held past their moment.
    add_index :participants, :github_token_revoke_after,
              where: "github_token IS NOT NULL",
              name: "index_participants_on_github_token_to_revoke"
  end
end
