# frozen_string_literal: true

require "test_helper"

# How GithubClient classifies a refusal. A 429 is a request to wait, so it must
# be retried rather than shown to a participant as GitHub refusing.
class GithubClientTest < ActiveSupport::TestCase
  def respond_with(status, body, headers = {})
    res = Net::HTTPResponse::CODE_TO_OBJ[status.to_s].new("1.1", status.to_s, "")
    res.instance_variable_set(:@read, true)
    res.instance_variable_set(:@body, body)
    headers.each { |k, v| res[k] = v }
    http = Object.new
    http.define_singleton_method(:request) { |_req| res }
    original = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) { |*_args, **_kw, &blk| blk.call(http) }
    begin
      yield
    ensure
      Net::HTTP.define_singleton_method(:start, original)
    end
  end

  test "a 429 is transient and the log keeps GitHub's reason and Retry-After" do
    respond_with(429, { message: "Too many requests" }.to_json, "retry-after" => "30") do
      error = assert_raises(GithubClient::TransientError) do
        GithubClient.new("t").create_codespace(repository_id: 1)
      end
      assert_equal 429, error.status
      assert_includes error.message, "Too many requests"
      assert_includes error.message, "retry-after 30s"
    end
  end

  test "a 429 with no JSON body still logs what GitHub sent" do
    respond_with(429, "slow down", {}) do
      error = assert_raises(GithubClient::TransientError) do
        GithubClient.new("t").create_codespace(repository_id: 1)
      end
      assert_includes error.message, "slow down"
    end
  end

  test "a 403 stays a permanent refusal" do
    respond_with(403, { message: "Forbidden" }.to_json) do
      error = assert_raises(GithubClient::Error) do
        GithubClient.new("t").create_codespace(repository_id: 1)
      end
      assert_not_kind_of GithubClient::TransientError, error
    end
  end
end
