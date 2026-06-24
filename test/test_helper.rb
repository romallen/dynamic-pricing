ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"
require "ostruct"
require_relative "support/rate_api_helpers"

class ActiveSupport::TestCase
  # Run tests in parallel with specified workers
  parallelize(workers: 1)

  # Make RateApiHelpers available in every test class.
  include RateApiHelpers

  teardown { Rails.cache.clear }
end
