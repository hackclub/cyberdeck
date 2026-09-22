# frozen_string_literal: true

require "test_helper"

# The RSVP box, the Fillout hand-off, and the closed sign-ups behind it.
# See wiki/decisions/D-023-rsvp-to-airtable-fillout-prefill.md.
class RsvpsTest < ActionDispatch::IntegrationTest
  FORM = "https://forms.hackclub.com/cyberdeck-rsvp?source=site"

  setup do
    Rails.configuration.x.signups_open = false
    Rails.configuration.x.fillout_url = nil
  end

  teardown do
    Rails.configuration.x.signups_open = true
    Rails.configuration.x.fillout_url = nil
  end

  test "the landing page shows the RSVP box and no login while sign-ups are closed" do
    get root_path
    assert_response :success
    assert_select "form.rsvp input[type=email]", 2
    assert_select "form.rsvp[data-controller=prefill]", 2
    assert_select "a", text: "Log in", count: 0
    assert_select "a", text: "Get started", count: 0
    assert_select "a", text: "Conditions", count: 0
  end

  test "an RSVP is stored lowercased with its origin and queued for Airtable" do
    assert_enqueued_with(job: SyncRsvpJob) do
      post rsvp_path, params: { email: "  Ada@Example.com ", slot: "rsvp-end", utm_source: "slack", utm_campaign: "eoi" },
                      headers: { "CF-IPCountry" => "au" }
    end
    assert_redirected_to root_path(anchor: "rsvp-end")
    rsvp = Rsvp.sole
    assert_equal "ada@example.com", rsvp.email
    assert_equal "127.0.0.1", rsvp.ip
    assert_equal "AU", rsvp.country
    assert_equal "slack", rsvp.utm_source
    assert_equal "eoi", rsvp.utm_campaign
    assert_nil rsvp.utm_medium
    follow_redirect!
    assert_select ".rsvp-done", text: RsvpsController::DONE
    assert_select "form.rsvp", 0
  end

  test "Cloudflare's headers give the address and the country" do
    post rsvp_path, params: { email: "ada@example.com" },
                    headers: { "CF-Connecting-IP" => "203.0.113.9", "CF-IPCountry" => "au" }
    rsvp = Rsvp.sole
    assert_equal "203.0.113.9", rsvp.ip
    assert_equal "AU", rsvp.country
  end

  test "Cloudflare's placeholder country codes are dropped" do
    post rsvp_path, params: { email: "xx@example.com" }, headers: { "CF-IPCountry" => "XX" }
    assert_nil Rsvp.sole.country
  end

  test "utm parameters on the landing page ride along as hidden fields" do
    get root_path(utm_source: "slack", utm_medium: "announcement", ref: "ignored")
    assert_select "form.rsvp input[type=hidden][name=utm_source][value=slack]", 2
    assert_select "form.rsvp input[type=hidden][name=utm_medium][value=announcement]", 2
    assert_select "form.rsvp input[name=ref]", 0
  end

  test "the page carries its utm into the form, and the form back to the row" do
    get root_path(utm_source: "slack", utm_campaign: "eoi")
    post rsvp_path, params: { email: "ada@example.com" }.merge(form_utm)
    rsvp = Rsvp.sole
    assert_equal "slack", rsvp.utm_source
    assert_equal "eoi", rsvp.utm_campaign
  end

  test "nothing is kept on the device, so a later bare page carries no source" do
    get root_path(utm_source: "slack")
    get root_path
    assert_select "form.rsvp input[type=hidden][name=utm_source]", 0
    post rsvp_path, params: { email: "ada@example.com" }
    assert_nil Rsvp.sole.utm_source
  end

  test "a cookie left over from D-026 is expired and never read" do
    cookies[:utm] = { "utm_source" => "stale" }.to_json
    get root_path
    assert_select "form.rsvp input[type=hidden][name=utm_source]", 0
    assert_match(/utm=;/, set_cookie_header)
    post rsvp_path, params: { email: "ada@example.com" }
    assert_nil Rsvp.sole.utm_source
  end

  test "a typo keeps its source, because the page is rendered again" do
    post rsvp_path, params: { email: "not an email", utm_source: "slack" }
    assert_response 422
    assert_equal 0, Rsvp.count
    # The form comes back with the attribution still in it, so the retry is
    # credited without anything being stored.
    assert_select "form.rsvp input[type=hidden][name=utm_source][value=slack]", 2
    post rsvp_path, params: { email: "ada@example.com" }.merge(form_utm)
    assert_equal "slack", Rsvp.sole.utm_source
  end

  test "the address bar is rewritten only when it needs it" do
    get root_path(utm_source: "slack")
    assert_select "header.hero[data-controller=utm]", 1
    get root_path
    assert_select "header.hero[data-controller=utm]", 0
  end

  test "a post is stamped with the utm it carries" do
    post rsvp_path, params: { email: "ada@example.com", utm_source: "posted" }
    assert_equal "posted", Rsvp.sole.utm_source
  end

  test "with a Fillout form the RSVP goes on to it with the email filled" do
    Rails.configuration.x.fillout_url = FORM
    post rsvp_path, params: { email: "ada@example.com" }
    assert_response :see_other
    assert_equal "https://forms.hackclub.com/cyberdeck-rsvp?source=site&email=ada%40example.com", response.location
    assert_equal 1, Rsvp.count
  end

  test "the same email twice reads as done and stays one row" do
    2.times { post rsvp_path, params: { email: "ada@example.com" } }
    assert_equal 1, Rsvp.count
    assert_redirected_to root_path(anchor: "top")
    assert_equal RsvpsController::DONE, flash[:rsvp_done]
  end

  test "a repeat email also goes on to the form" do
    Rails.configuration.x.fillout_url = FORM
    Rsvp.create!(email: "ada@example.com")
    post rsvp_path, params: { email: "Ada@example.com" }
    assert_response :see_other
    assert_match %r{\Ahttps://forms\.hackclub\.com/}, response.location
    assert_equal 1, Rsvp.count
  end

  test "a bad email is refused and shown again" do
    post rsvp_path, params: { email: "not an email" }
    assert_equal 0, Rsvp.count
    assert_response 422
    assert_select "p.rsvp-error", RsvpsController::INVALID
    assert_select "form.rsvp input[type=email][value=?]", "not an email"
  end

  test "a filled honeypot is dropped, told yes, and not sent to the form" do
    Rails.configuration.x.fillout_url = FORM
    post rsvp_path, params: { email: "bot@example.com", company: "Bots Inc" }
    assert_equal 0, Rsvp.count
    assert_redirected_to root_path(anchor: "top")
    assert_equal RsvpsController::DONE, flash[:rsvp_done]
  end

  test "the login chain is closed" do
    get start_path
    assert_redirected_to root_path
    get connect_path(provider: "hack_club")
    assert_redirected_to root_path
    get done_path
    assert_redirected_to root_path
  end

  test "the OmniAuth request phase refuses while closed" do
    OmniAuth.config.test_mode = true
    post "/auth/hack_club"
    assert_redirected_to root_path
    assert_equal 0, Participant.count
  ensure
    OmniAuth.config.test_mode = false
  end

  test "with sign-ups open the landing page shows the buttons again" do
    Rails.configuration.x.signups_open = true
    get root_path
    assert_select "a", text: "Get started"
    assert_select "form.rsvp", 0
  end
end
