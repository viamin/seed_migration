require File.expand_path("../boot", __FILE__)

require "logger" # Ensure Logger constant is loaded before ActiveSupport references it (Rails 7 compatibility)
require "rails/all"

Bundler.require(*Rails.groups)
require "seed_migration"

module Dummy
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults "#{Rails::VERSION::MAJOR}.0"

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
