# frozen_string_literal: true
# typed: true

module Constants
  DISPOSABLE_EMAIL_BLOCKLIST_URL = "https://raw.githubusercontent.com/disposable-email-domains/disposable-email-domains/refs/heads/main/disposable_email_blocklist.conf"
  DISPOSABLE_EMAIL_BLOCKLIST_FILE_PATH = Rails.root.join("tmp", "blocklist.conf")
end
