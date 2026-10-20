# PromptEngine encrypts the API keys you can save on its settings page
# (`encrypts :anthropic_api_key`). Active Record encryption needs keys; unless they
# are set in credentials, derive them from secret_key_base so nothing secret is committed.
Rails.application.config.after_initialize do
  next if Rails.application.credentials.dig(:active_record_encryption, :primary_key)

  keys = Rails.application.key_generator
  ActiveRecord::Encryption.configure(
    primary_key: keys.generate_key("active_record_encryption.primary_key", 32).unpack1("H*"),
    deterministic_key: keys.generate_key("active_record_encryption.deterministic_key", 32).unpack1("H*"),
    key_derivation_salt: keys.generate_key("active_record_encryption.key_derivation_salt", 32).unpack1("H*")
  )
end
