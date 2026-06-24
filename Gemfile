source "https://rubygems.org"

ruby "3.2.6"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 7.1.5", ">= 7.1.5.2"

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"

gem "redis", ">= 5.0"

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[windows jruby]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# HTTP client for external API call
gem "httparty"

# Telemetry — OpenTelemetry traces + metrics. All loaded with require: false and
# activated only by config/initializers/opentelemetry.rb when OTEL_ENABLED=true,
# so a default boot pulls in none of it. Metrics gems are still beta upstream.
gem "opentelemetry-exporter-otlp", require: false
gem "opentelemetry-exporter-otlp-metrics", require: false
gem "opentelemetry-instrumentation-all", require: false
gem "opentelemetry-metrics-sdk", require: false
gem "opentelemetry-sdk", require: false

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
# gem "rack-cors"

gem "lograge"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[mri windows]
  gem "dotenv-rails"

  gem "rbs",                 require: false
  gem "rubocop",             require: false
  gem "rubocop-minitest",    require: false
  gem "rubocop-performance", require: false
  gem "rubocop-rails",       require: false
end

group :development do
  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"

  # Live reloading for development
  gem "listen", "~> 3.10"
end

group :production do
  gem "aws-sdk-secretsmanager", require: false
end
