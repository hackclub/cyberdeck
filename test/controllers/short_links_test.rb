# frozen_string_literal: true

require "test_helper"

# A short link renders the landing page with the code's utm values in the
# RSVP form, and nothing is stored on the device. The codes come from the
# "Short Links" table of the program base, so the tests stand a fake table in
# its place. See D-027 and D-029.
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

  test "a short link renders the landing page and asks for a clean address bar" do
    get "/k3"
    assert_response :success
    assert_select "form.rsvp", 2
    assert_select "header.hero[data-controller=utm]", 1
  end

  test "the code becomes the attribution on the RSVP" do
    get "/k3"
    post rsvp_path, params: { email: "ada@example.com" }.merge(form_utm)
    rsvp = Rsvp.sole
    assert_equal "slack", rsvp.utm_source
    assert_equal "channel", rsvp.utm_medium
    assert_equal "launch", rsvp.utm_campaign
    assert_equal "ysws-ads", rsvp.utm_content
  end

  test "a code with fewer fields leaves the rest empty" do
    get "/k5"
    post rsvp_path, params: { email: "ada@example.com" }.merge(form_utm)
    assert_equal "dm", Rsvp.sole.utm_medium
    assert_nil Rsvp.sole.utm_content
  end

  test "an unknown code still reaches the program, with no attribution" do
    get "/nosuchcode"
    assert_response :success
    assert_select "form.rsvp", 2
    post rsvp_path, params: { email: "ada@example.com" }.merge(form_utm)
    assert_nil Rsvp.sole.utm_source
  end

  test "a short link writes nothing to the device" do
    get "/k3"
    assert_no_match(/utm=/, set_cookie_header)
    # A later bare page knows nothing, because the form was the only carrier.
    get root_path
    post rsvp_path, params: { email: "ada@example.com" }.merge(form_utm)
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

  test "the link someone followed last is the page they submit from" do
    get "/k3"
    get "/k5"
    post rsvp_path, params: { email: "ada@example.com" }.merge(form_utm)
    assert_equal "dm", Rsvp.sole.utm_medium
    assert_nil Rsvp.sole.utm_content
  end
end
