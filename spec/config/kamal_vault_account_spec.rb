# frozen_string_literal: true

require "rails_helper"

# @lat: [[kamal-vault-account-indirection#Why .kamal/secrets-common must never name the vault account literally]]
RSpec.describe ".kamal/secrets-common" do
  let(:secrets_file_text) { Rails.root.join(".kamal", "secrets-common").read }

  def account_arguments(text)
    text.scan(/--account\s+(\S+)/).flatten
  end

  it "names the account by variable, never by value" do
    literals = account_arguments(secrets_file_text).reject { |arg| arg.start_with?("$") }

    # The commented 1Password example ships with Kamal and is not our account.
    literals -= ["my-account"]

    expect(literals).to be_empty,
      "--account must come from SWAY_SECRETS_ACCOUNT through scripts/lib/secrets.sh. Found #{literals.length} " \
      "literal value(s) in .kamal/secrets-common. The value is not printed here on purpose."
  end

  # @lat: [[kamal-vault-account-indirection#Why the account variable is resolved on its own line, not nested inside the fetch]]
  it "resolves the fetch command on its own line, not nested inside the fetch" do
    expect(secrets_file_text).to match(%r{^SWAY_SECRETS_FETCH=\$\(bash scripts/lib/secrets\.sh fetch-command\)$})

    fetch_line = secrets_file_text[/^SECRETS=.*$/].to_s
    expect(fetch_line).to start_with("SECRETS=$($SWAY_SECRETS_FETCH ")
    expect(fetch_line.delete_prefix("SECRETS=$(")).not_to include("$("),
      "the fetch line cannot use $(...) inside it — Kamal never gives a kamal secrets line to a shell."
  end
end
