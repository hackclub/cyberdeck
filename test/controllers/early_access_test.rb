# frozen_string_literal: true

require "test_helper"

# The hidden link for Hack Club email addresses. See D-030.
class EarlyAccessTest < ActionDispatch::IntegrationTest
  TOKEN = "t" * 32

  setup do
    @was_open = Rails.configuration.x.signups_open
    Rails.configuration.x.signups_open = false
    ENV["EARLY_ACCESS_TOKEN"] = TOKEN
    OmniAuth.config.test_mode = true
  end

  teardown do
    Rails.configuration.x.signups_open = @was_open
    ENV.delete("EARLY_ACCESS_TOKEN")
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:hack_club] = nil
  end

  def mock_email(email)
    OmniAuth.config.mock_auth[:hack_club] = OmniAuth::AuthHash.new(
      provider: "hack_club", uid: "ident!#{email}",
      info: { email: email, first_name: "A", last_name: "B" },
      credentials: { token: "hca" },
      extra: { raw_info: { "verification_status" => "verified", "ysws_eligible" => true } }
    )
  end

  test "a wrong token is a 404" do
    get "/early/#{'x' * 32}"
    assert_response :not_found
  end

  test "no token set is a 404" do
    ENV.delete("EARLY_ACCESS_TOKEN")
    get "/early/#{TOKEN}"
    assert_response :not_found
  end

  test "the right token opens /start, and without it /start redirects" do
    get start_path
    assert_redirected_to root_path
    get "/early/#{TOKEN}"
    assert_redirected_to start_path
    get start_path
    assert_response :success
  end

  test "a hackclub.com email signs in" do
    get "/early/#{TOKEN}"
    mock_email("friend@hackclub.com")
    get "/auth/hack_club/callback"
    assert Participant.exists?(hca_id: "ident!friend@hackclub.com")
    get connect_path(provider: "hackatime")
    assert_response :success
  end

  test "another email is refused and nothing is saved" do
    get "/early/#{TOKEN}"
    mock_email("someone@example.com")
    get "/auth/hack_club/callback"
    assert_redirected_to root_path
    assert_not Participant.exists?(hca_id: "ident!someone@example.com")
  end

  test "a lookalike domain is refused" do
    get "/early/#{TOKEN}"
    mock_email("x@hackclub.com.evil.test")
    get "/auth/hack_club/callback"
    assert_not Participant.exists?(hca_id: "ident!x@hackclub.com.evil.test")
  end
end
