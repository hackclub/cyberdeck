# frozen_string_literal: true

# Runs the GitHub calls that turn a project into a repository and, for a
# Codespace project, a working Codespace. Ordered, because each step needs the
# one before it.
#
#   1. generate the participant's repo from the program template
#   2. write HACKATIME_API_KEY as a user secret scoped to that repo
#   3. create the Codespace
#
# A project of kind "local" stops after step 1. The participant brings their
# own editor and clones the repository. See wiki/decisions/D-019-projects.md.
#
# Step 2 must land before step 3, or the dev container starts with no key and
# the Hackatime extension shows a modal on every heartbeat flush.
# See wiki/concepts/codespaces-provisioning.md.
#
# The GitHub token is put on a clock only when the work is truly over: on
# success, on a terminal failure, or when retries are exhausted. Releasing it
# in an ensure block would revoke it before the first retry could use it.
#
# It is not killed on the spot. The participant keeps it for
# Participant::TOKEN_GRACE so a failed run can be retried without reconnecting
# GitHub, and RevokeGithubTokenJob kills it once that is up.
class ProvisionCodespaceJob < ApplicationJob
  queue_as :default

  # GitHub is sometimes slow to make a freshly generated repository available
  # to the secrets endpoint. Retry the transient case rather than spoiling a
  # participant's first impression of the program.
  retry_on GithubClient::TransientError, wait: :polynomially_longer, attempts: 5 do |job, error|
    # Attempts exhausted. Leave an explanation rather than a record stuck at
    # "running", and only now release the token.
    Rails.logger.error("ProvisionCodespaceJob gave up: #{error.message}")
    provisioning = Provisioning.find_by(id: job.arguments.first)
    next unless provisioning

    provisioning.fail!("GitHub would not finish setting your project up. Try again from the start.")
    provisioning.participant.hold_github_token!
  end

  def perform(provisioning_id)
    provisioning = Provisioning.find(provisioning_id)
    participant  = provisioning.participant
    token        = participant.github_token

    return provisioning.fail!("Your GitHub sign-in expired. Start again from the dashboard.") if token.blank?
    return finish(provisioning, participant, ineligible_message(participant)) unless participant.may_provision?

    # Fail early and readably on missing configuration. Without this the first
    # ENV.fetch raises a KeyError, which retry_on does not catch, and the
    # record sits at "running" while the status page polls forever.
    owner = ENV["TEMPLATE_OWNER"].presence
    repo_name = ENV["TEMPLATE_REPO"].presence
    if owner.nil? || repo_name.nil?
      Rails.logger.error("ProvisionCodespaceJob: TEMPLATE_OWNER and TEMPLATE_REPO are not set")
      return finish(provisioning, participant,
                    "The program template is not set up yet. That is our problem, not yours. " \
                    "Let us know in the program channel.")
    end

    client = GithubClient.new(token)

    provisioning.step!("repo")
    repo = find_or_generate_repo(client, provisioning, owner, repo_name)
    provisioning.update!(repo_full_name: repo["full_name"], repo_id: repo["id"])

    if provisioning.project.local?
      provisioning.complete!
      participant.hold_github_token!
      return
    end

    provisioning.step!("secret")
    client.put_codespaces_user_secret(
      name: "HACKATIME_API_KEY",
      value: participant.hackatime_api_key,
      repository_ids: [ repo["id"] ]
    )

    provisioning.step!("codespace")
    # A repository generated from a template exists before its first commit
    # does. Creating a Codespace against it then fails with "The 'ref' provided
    # was invalid", because GitHub cannot resolve the default branch yet.
    wait_for_default_branch(client, repo)
    codespace = client.create_codespace(repository_id: repo["id"])
    provisioning.update!(codespace_name: codespace["name"], codespace_url: codespace["web_url"])

    provisioning.complete!
    participant.hold_github_token!
  rescue GithubClient::TransientError => e
    # Let retry_on handle it. The token has to survive for the next attempt.
    Rails.logger.error("ProvisionCodespaceJob: #{e.message}")
    raise
  rescue GithubClient::Error => e
    # GitHub has decided. Retrying would only repeat it.
    Rails.logger.error("ProvisionCodespaceJob: #{e.message}")
    finish(provisioning, participant, github_refusal_message(e))
  rescue StandardError => e
    # Anything unexpected still has to leave a readable record behind.
    Rails.logger.error("ProvisionCodespaceJob: #{e.class}: #{e.message}")
    finish(provisioning, participant, "Something went wrong setting your project up. " \
                                      "Let us know in the program channel.")
    raise
  end

  private

  # How long to let GitHub finish writing the template commit. Observed to take
  # a few seconds; the ceiling is generous so a slow day does not fail a run.
  BRANCH_ATTEMPTS = 12
  BRANCH_WAIT     = 2.seconds

  # Blocks until the repository's default branch resolves. Raises a transient
  # error if it never does, so retry_on gets a chance rather than the
  # participant getting "GitHub refused to set your project up".
  def wait_for_default_branch(client, repo)
    name = repo["default_branch"].presence || "main"

    BRANCH_ATTEMPTS.times do |attempt|
      return if client.branch(repo["full_name"], name)

      sleep(BRANCH_WAIT) unless attempt == BRANCH_ATTEMPTS - 1
    end

    raise GithubClient::TransientError,
          "#{repo['full_name']} still has no #{name} branch after " \
          "#{BRANCH_ATTEMPTS * BRANCH_WAIT.to_i}s"
  end

  # A participant who comes back after a half-finished run already owns the
  # repository, and GitHub answers a second generate with 422. Reuse it, but
  # only once we are sure it is ours.
  #
  # Never adopt a repository the participant made themselves. Writing a
  # Codespaces secret into someone's unrelated project, or opening a Codespace
  # in it, is not ours to do. Two independent ways to be sure:
  #
  #   1. this app recorded that repository id against this participant before
  #   2. GitHub says it was generated from our template
  #
  # Either is enough. Neither, and we leave their repository alone and use a
  # different name.
  def find_or_generate_repo(client, provisioning, owner, template)
    generate(client, provisioning, owner, template)
  rescue GithubClient::Error => e
    raise unless e.status == 422

    login = client.viewer["login"]
    existing = client.repo("#{login}/#{provisioning.repo_name}")
    raise unless existing

    if ours?(provisioning, existing, owner, template)
      Rails.logger.info("ProvisionCodespaceJob: reusing #{existing["full_name"]}")
      return existing
    end

    # Their own repository sits at that name. Take a different one.
    Rails.logger.info("ProvisionCodespaceJob: #{existing["full_name"]} is not ours, picking a new name")
    provisioning.update!(repo_name: free_repo_name(client, login, provisioning.repo_name))
    generate(client, provisioning, owner, template)
  end

  # Claims the name in our own records BEFORE asking GitHub for it, so a crash
  # between the request and the response still leaves evidence rather than an
  # orphaned repository nobody can identify later.
  def generate(client, provisioning, owner, template)
    claim = ProgramRepository.claim!(
      participant: provisioning.participant,
      provisioning: provisioning,
      full_name: "#{client.viewer["login"]}/#{provisioning.repo_name}",
      template: "#{owner}/#{template}"
    )

    repo = client.generate_from_template(
      template_owner: owner,
      template_repo: template,
      name: provisioning.repo_name,
      description: "My cyberdeck build",
      private: false
    )
    claim.confirm!(repo)
    repo
  rescue StandardError
    # An unconfirmed claim is a lead, not proof. Keep it only if the
    # repository might actually exist, which a 422 says it does not.
    claim&.destroy if defined?(claim) && claim&.github_repo_id.nil?
    raise
  end

  # Never adopt a repository the participant made themselves. Writing a
  # Codespaces secret into someone's unrelated project, or opening a Codespace
  # in it, is not ours to do. Two independent ways to be sure:
  #
  #   1. our own records say this program created it
  #   2. GitHub says it was generated from our template
  #
  # Either is enough. The first survives a template rename; the second
  # survives us losing the row.
  #
  # And never adopt, for this project, a repository that another of the
  # participant's projects already holds. That is the first project's
  # repository, and the second project must get its own.
  def ours?(provisioning, repo, owner, template)
    held_elsewhere = Project.where(repo_id: repo["id"]).where.not(id: provisioning.project_id).exists?
    return false if held_elsewhere

    recorded = ProgramRepository.created_by_program?(
      participant: provisioning.participant, repo: repo
    )
    from_template = repo.dig("template_repository", "full_name") == "#{owner}/#{template}"
    recorded || from_template
  end

  # cyberdeck-ada, cyberdeck-ada-2, cyberdeck-ada-3 ...
  def free_repo_name(client, login, base)
    base = base.sub(/-\d+\z/, "")
    (2..20).each do |n|
      candidate = "#{base}-#{n}"
      return candidate if client.repo("#{login}/#{candidate}").nil?
    end
    "#{base}-#{SecureRandom.hex(3)}"
  end

  def github_refusal_message(error)
    case error.status
    when 401, 403
      "GitHub would not let us set your project up. Reconnect GitHub and try again."
    when 422
      "There is already something at that name on your GitHub account. " \
        "Tell us in the program channel and we will sort it."
    else
      "GitHub refused to set your project up. Tell us in the program channel."
    end
  end

  # Marks the attempt failed and starts the token's clock, because nothing else
  # will run for this provisioning. The token stays usable for the grace period
  # so the participant can retry without reconnecting GitHub.
  def finish(provisioning, participant, message)
    provisioning.fail!(message)
    participant.hold_github_token!
    nil
  end

  def ineligible_message(participant)
    if participant.hackatime_banned?
      "Hackatime has this account marked as banned, so it cannot take part."
    else
      "This account cannot take part. If you think that is wrong, ask in the program channel."
    end
  end
end
