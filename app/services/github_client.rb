# frozen_string_literal: true

require "rbnacl"
require "base64"

# Talks to GitHub as one participant, using their own user access token.
#
# Every call here acts on the participant's account, so the token is passed in
# per instance and never cached on the class. See wiki/concepts/token-custody.md
# for how long the caller is allowed to hold it.
class GithubClient
  API = "https://api.github.com"

  # Carries the status so callers can tell a permanent refusal from a blip.
  class Error < StandardError
    attr_reader :status, :body

    def initialize(message, status: nil, body: nil)
      @status = status
      @body = body
      super(message)
    end
  end

  # Worth retrying: a server-side blip, a resource GitHub has not made
  # visible yet, or a 429 that asks us to slow down. Everything else is a
  # decision GitHub will repeat.
  class TransientError < Error; end

  def initialize(token)
    @token = token
  end

  # Creates the participant's own repository from the program template.
  # They own it, which is what makes the Codespaces user secret reach it and
  # what makes the Code URL theirs for the ship. See wiki/concepts/shipped-project.md.
  def generate_from_template(template_owner:, template_repo:, name:, description: nil, private: false)
    post("/repos/#{template_owner}/#{template_repo}/generate",
         name: name,
         description: description,
         private: private,
         include_all_branches: false)
  end

  # Writes HACKATIME_API_KEY as a Codespaces user secret, scoped to just this
  # repository. GitHub only injects user secrets into a codespace when the
  # participant has write access to its repository, which they do because they
  # own it. See wiki/concepts/codespaces-provisioning.md.
  def put_codespaces_user_secret(name:, value:, repository_ids:)
    key = get("/user/codespaces/secrets/public-key")
    put("/user/codespaces/secrets/#{name}",
        encrypted_value: seal(value, key.fetch("key")),
        key_id: key.fetch("key_id"),
        selected_repository_ids: Array(repository_ids))
  end

  def create_codespace(repository_id:, machine: nil, ref: nil, idle_timeout_minutes: 30, retention_period_minutes: 10_080)
    body = {
      repository_id: repository_id,
      idle_timeout_minutes: idle_timeout_minutes,
      retention_period_minutes: retention_period_minutes
    }
    body[:machine] = machine if machine
    body[:ref] = ref if ref
    post("/user/codespaces", **body)
  end

  def machines_for(owner:, repo:)
    get("/repos/#{owner}/#{repo}/codespaces/machines").fetch("machines", [])
  end

  def viewer
    get("/user")
  end

  # Returns the repository, or nil when it does not exist. Used to recover
  # from a name that is already taken.
  def repo(full_name)
    get("/repos/#{full_name}")
  rescue Error => e
    raise unless e.status == 404

    nil
  end

  # Returns the Codespace, or nil when GitHub no longer has it. GitHub answers
  # this only for the Codespace's owner, which is why the token must outlive
  # the run. See wiki/decisions/D-015-keep-github-token.md.
  def codespace(name)
    get("/user/codespaces/#{name}")
  rescue Error => e
    raise unless e.status == 404

    nil
  end

  # Returns the branch, or nil when it does not exist yet. Generating a repo
  # from a template creates the repository before it finishes writing the
  # commit, so the default branch can be missing for a few seconds.
  def branch(full_name, name)
    get("/repos/#{full_name}/branches/#{name}")
  rescue Error => e
    raise unless e.status == 404

    nil
  end

  # Kills the token at GitHub rather than just forgetting it locally.
  # An OAuth App token does not expire on its own, so dropping the row would
  # leave a live credential that can push to every public repository the
  # participant owns. See wiki/decisions/D-013-oauth-app-with-revoke.md.
  #
  # Authenticated with the app's own client id and secret, not the token.
  def self.revoke!(token:, client_id:, client_secret:)
    uri = URI.join(API, "/applications/#{client_id}/token")
    req = Net::HTTP::Delete.new(uri)
    req.basic_auth(client_id, client_secret)
    req["Accept"] = "application/vnd.github+json"
    req["X-GitHub-Api-Version"] = "2022-11-28"
    req["Content-Type"] = "application/json"
    req.body = { access_token: token }.to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    # 204 means revoked. 404 means it was already gone, which is also fine.
    unless res.is_a?(Net::HTTPSuccess) || res.is_a?(Net::HTTPNotFound)
      Rails.logger.error("github token revoke failed: #{res.code}")
    end
    res.code.to_i
  end

  private

  attr_reader :token

  # GitHub requires secrets to be sealed with libsodium against the account's
  # public key, so GitHub never sees the plaintext in transit.
  # https://docs.github.com/en/rest/guides/encrypting-secrets-for-the-rest-api
  def seal(value, base64_public_key)
    public_key = RbNaCl::PublicKey.new(Base64.decode64(base64_public_key))
    sealed = RbNaCl::Boxes::Sealed.from_public_key(public_key).encrypt(value)
    Base64.strict_encode64(sealed)
  end

  def get(path)    = request(Net::HTTP::Get, path)
  def post(path, **body) = request(Net::HTTP::Post, path, body)
  def put(path, **body)  = request(Net::HTTP::Put, path, body)

  def request(klass, path, body = nil)
    uri = URI.join(API, path)
    req = klass.new(uri)
    req["Authorization"] = "Bearer #{token}"
    req["Accept"] = "application/vnd.github+json"
    req["X-GitHub-Api-Version"] = "2022-11-28"
    req["User-Agent"] = "cyberdeck"
    if body
      req["Content-Type"] = "application/json"
      req.body = body.compact.to_json
    end

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

    unless res.is_a?(Net::HTTPSuccess)
      status = res.code.to_i
      # The body can echo the request, so keep only GitHub's own message.
      detail = begin
        JSON.parse(res.body.to_s)["message"]
      rescue StandardError
        nil
      end
      # A 429 is GitHub's own throttle, so its body is safe to log. Without
      # it, and without Retry-After, a refusal says nothing about why.
      if status == 429
        detail ||= res.body.to_s.squish.first(200).presence
        retry_after = res["retry-after"]
        wait = "retry-after #{retry_after}s" if retry_after
        detail = [ detail, wait ].compact.join(", ").presence
      end
      message = "GitHub #{klass::METHOD} #{path} -> #{status}#{" #{detail}" if detail}"
      # 5xx is GitHub having a moment. 404 right after a write is GitHub not
      # having caught up yet. 429 is a request to wait. None is a verdict.
      # Anything else is.
      klass_for = (status >= 500 || status == 404 || status == 429) ? TransientError : Error
      raise klass_for.new(message, status: status, body: detail)
    end

    res.body.to_s.empty? ? {} : JSON.parse(res.body)
  end
end
