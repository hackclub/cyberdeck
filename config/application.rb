require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Cyberdeck
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # lib/omniauth holds an OmniAuth strategy, which is required explicitly in
    # config/initializers/omniauth.rb. Zeitwerk would otherwise expect the
    # constant to be spelled Omniauth rather than OmniAuth.
    config.autoload_lib(ignore: %w[assets tasks omniauth])

    # Whether anyone may sign in and set up. Closed unless SIGNUPS_OPEN=1.
    # While closed the landing page collects RSVP emails instead, and every
    # route into the login chain sends people back to it. Armand, 2026-09-21.
    # See wiki/decisions/D-022-signups-closed-rsvp.md.
    config.x.signups_open = ENV["SIGNUPS_OPEN"] == "1"

    # The Fillout form an RSVP is sent on to, with ?email= appended. Blank
    # means no form yet: the box says thanks and stays. Armand, 2026-09-21.
    config.x.fillout_url = ENV["FILLOUT_URL"].presence

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
