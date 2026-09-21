# frozen_string_literal: true

require "test_helper"

# A short link writes the utm cookie and lands on a clean home page. The
# codes come from the "Short Links" table of the program base, so the tests
# stand a fake table in its place.
# See wiki/decisions/D-027-short-links.md.
class ShortLinksTest < ActionDispatch::IntegrationTest
  LINKS = {
    "k3" => { "utm_source" => "slack", "utm_medium" => "channel",
              "utm_campaign" => "launch", "utm_content" => "ysws-ads" },
    "k5" => { "utm_source" => "slack", "utm_medium" => "dm", "utm_campaign" => "launch" }
  }.freeze

  setup do
    Rails.configuration.x.signups_open = false
    ShortLink.singleton_class.alias_method(:real_all, :all)
    ShortLink.define_singleton_method(:all) { LINKS }
  end

  teardown do
    Rails.configuration.x.signups_open = true
    ShortLink.singleton_class.alias_method(:all, :real_all)
  end

  test "a short link lands on the home page with nothing in the address bar" do
    get "/k3"
    assert_redirected_to root_path
    assert_equal "/", response.location.sub(%r{\Ahttps?://[^/]+}, "")
  end

  test "the code becomes the attribution on the RSVP" do
    get "/k3"
    post rsvp_path, params: { email: "ada@example.com" }
    rsvp = Rsvp.sole
    assert_equal "slack", rsvp.utm_source
    assert_equal "channel", rsvp.utm_medium
    assert_equal "launch", rsvp.utm_campaign
    assert_equal "ysws-ads", rsvp.utm_content
  end

  test "a code with fewer fields leaves the rest empty" do
    get "/k5"
    post rsvp_path, params: { email: "ada@example.com" }
    assert_equal "dm", Rsvp.sole.utm_medium
    assert_nil Rsvp.sole.utm_content
  end

  test "an unknown code still reaches the program, with no attribution" do
    get "/nosuchcode"
    assert_redirected_to root_path
    post rsvp_path, params: { email: "ada@example.com" }
    assert_nil Rsvp.sole.utm_source
  end

  test "a code of the wrong shape is not looked up" do
    assert_nil ShortLink.utm_for("A!")
    assert_nil ShortLink.utm_for("x")
    assert_equal "slack", ShortLink.utm_for("K3")["utm_source"]
  end

  test "the short link route never shadows a real one" do
    get start_path
    assert_equal "/start", path
    assert_redirected_to root_path

    get done_path
    assert_equal "/done", path

    get rails_health_check_path
    assert_response :success
  end

  test "a short link overrides an older one" do
    get "/k3"
    get "/k5"
    post rsvp_path, params: { email: "ada@example.com" }
    assert_equal "dm", Rsvp.sole.utm_medium
  end
end
