ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

class ActionDispatch::IntegrationTest
  # The utm values the rendered RSVP form would post. The form is the only
  # carrier for the attribution, so a test that posts these is testing the
  # chain a browser walks. See wiki/decisions/D-029-attribution-without-a-cookie.md.
  def form_utm
    form = css_select("form.rsvp").first
    return {} if form.nil?

    form.css("input[type=hidden]").each_with_object({}) do |input, acc|
      acc[input["name"]] = input["value"] if input["name"].to_s.start_with?("utm_")
    end
  end
end

class ActionDispatch::IntegrationTest
  # Set-Cookie, whatever case and shape the Rack version returns it in.
  def set_cookie_header = Array(response.headers["set-cookie"] || response.headers["Set-Cookie"]).join("\n")
end
