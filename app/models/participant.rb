# frozen_string_literal: true

class Participant < ApplicationRecord
  # Tokens and keys are encrypted at rest with Active Record Encryption.
  # Non-deterministic (the default) so the same value encrypts differently
  # each time and cannot be matched by an attacker with read access.
  # Rotation is supported for non-deterministic attributes.
  encrypts :hca_token
  encrypts :hca_refresh_token
  encrypts :hackatime_token
  encrypts :hackatime_api_key
  encrypts :github_token
  encrypts :github_refresh_token

  # Deterministic so the app can look a participant up by email when matching
  # against Hackatime's address list or the Unified DB.
  encrypts :email, deterministic: true, downcase: true

  # Hack Club Auth's identity id, e.g. "ident!abc123". The primary key for a
  # person across all three services.
  validates :hca_id, presence: true, uniqueness: true

  has_many :projects, dependent: :destroy
  has_many :provisionings, dependent: :destroy
  has_many :program_repositories, dependent: :destroy

  TRUST_LEVELS = %w[blue yellow green red].freeze

  # Hack Club Auth's verification_status. "ineligible" is the one that means
  # banned: the identity is permabanned upstream.
  BLOCKED_STATUS = "ineligible"

  # Participation is default-allow. Identity verification is NOT required to
  # take part, so an unknown or pending status lets someone in. Only an
  # explicit ban keeps them out.
  #
  # This is deliberate: verification can take days, and making a teenager wait
  # on it before they can even start building loses them. Eligibility is
  # checked again at submission time, where it actually has to hold.
  def blocked?
    verification_status == BLOCKED_STATUS
  end

  def may_participate? = !blocked?

  # Verified and confirmed under 19. Not a gate on taking part, but worth
  # showing on the dashboard and worth knowing before a prize is shipped.
  def eligibility_confirmed? = verification_status == "verified" && ysws_eligible?

  # Verified, but Hack Club Auth says not YSWS eligible, which in practice
  # means aged out. They may still build. Their submission will need an
  # Override Age Justification in the Unified DB.
  def aged_out? = verification_status == "verified" && !ysws_eligible?

  # A red trust level means Hackatime banned them for fraud. The handbook says
  # to stop there. See wiki/concepts/hackatime.md.
  def hackatime_banned?
    hackatime_trust_level == "red"
  end

  def may_provision?
    may_participate? && !hackatime_banned?
  end

  # Where the chain has got to. Drives the dashboard.
  def hackatime_connected? = hackatime_api_key.present?
  def github_connected?    = github_token.present?

  # A repository name the participant will recognise in their own account.
  # The first project is cyberdeck-<login>, the second cyberdeck-<login>-2,
  # and so on. The job picks a free name if GitHub already has one there.
  def suggested_repo_name(number = 1)
    base = github_login.presence || first_name.presence || "build"
    name = "cyberdeck-#{base.parameterize}"
    number > 1 ? "#{name}-#{number}" : name
  end

  # Whether the three accounts are all connected. Hack Club Auth is implied by
  # the row existing.
  def connected? = hackatime_connected? && github_connected?

  # Armand's rule of 2026-09-16: the first project is the only project until
  # it is set up. After that, another may start, as long as nothing else is
  # still setting up. A brand new participant has no project, and creating the
  # first one is not "another", so that case is handled by the caller.
  def may_start_another_project?
    projects.ready.exists? && !projects.setting_up.exists?
  end

  # The GitHub token is held only for the length of a provisioning run.
  # See wiki/concepts/token-custody.md.
  def discard_github_token!
    update!(github_token: nil, github_refresh_token: nil,
            github_token_expires_at: nil, github_token_revoke_after: nil)
  end

  # The token is kept for as long as the participant is in the program.
  #
  # It has to be. VerifyProvisioningsJob checks that their repository and
  # Codespace still exist, and asking GitHub about a Codespace needs the token
  # of the person who owns it. A token that died after a day would leave every
  # older participant unverifiable.
  #
  # The cost: a `public_repo` token, which can write to every public repository
  # they own, stays in the database. It is encrypted at rest and filtered from
  # logs, and revoked when they are blocked. See wiki/decisions/D-013.
  def hold_github_token!
    return if github_token.blank?
    return if github_token_revoke_after.nil?

    # Clear an expiry left over from when tokens were revoked after a day.
    update!(github_token_revoke_after: nil)
  end

  # Tokens someone has explicitly scheduled for revocation. Nothing sets this
  # automatically any more, but the sweeper still honours it, so marking a
  # token for death stays a one-line change.
  scope :github_token_due_for_revoke, lambda {
    where.not(github_token: nil).where(github_token_revoke_after: ..Time.current)
  }

  # Kills the token at GitHub rather than only forgetting it here. An OAuth App
  # token never expires on its own, so dropping the row alone would leave a
  # live credential that can push to every public repository the participant
  # owns. Always clears the local copy, even when the call to GitHub fails.
  def revoke_github_token!
    token = github_token
    return if token.blank?

    github = Rails.application.credentials.github || {}
    if github[:client_id].present?
      GithubClient.revoke!(token: token,
                           client_id: github[:client_id],
                           client_secret: github[:client_secret])
    end
    discard_github_token!
  rescue StandardError => e
    Rails.logger.error("github token revoke raised: #{e.class}")
    discard_github_token!
  end
end
