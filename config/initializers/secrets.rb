# In production, set SECRETS_ARN to an AWS Secrets Manager ARN containing a
# JSON object of key/value pairs. Each key is merged into ENV (existing values
# win, so platform-injected vars can still override).
#
# Other providers (GCP Secret Manager, HashiCorp Vault, K8s secrets) that
# inject vars at the platform level don't need this file at all.
return unless Rails.env.production?
return unless (arn = ENV["SECRETS_ARN"])

require "aws-sdk-secretsmanager"

begin
  secret = Aws::SecretsManager::Client.new.get_secret_value(secret_id: arn)
  JSON.parse(secret.secret_string).each { |k, v| ENV[k.to_s] ||= v.to_s }
rescue StandardError => e
  raise "Failed to load secrets from #{arn}: #{e.message}"
end
