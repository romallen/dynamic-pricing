# Set SECRETS_ARN in production to an AWS Secrets Manager ARN (JSON key/value).
# Each key is merged into ENV; existing values win so platform vars take precedence.
return unless Rails.env.production?
return unless (arn = ENV.fetch("SECRETS_ARN", nil))

require "aws-sdk-secretsmanager"

begin
  secret = Aws::SecretsManager::Client.new.get_secret_value(secret_id: arn)
  JSON.parse(secret.secret_string).each { |k, v| ENV[k.to_s] ||= v.to_s }
rescue StandardError => e
  raise "Failed to load secrets from #{arn}: #{e.message}"
end
