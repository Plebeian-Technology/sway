# frozen_string_literal: true

require "rails_helper"
require "erb"
require "open3"
require "yaml"

# @lat: [[active-record-encryption-keys]]
RSpec.describe "Active Record encryption keys" do
  def key_names
    %w[
      ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
      ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
      ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
    ]
  end

  # @lat: [[active-record-encryption-keys#Absent keys do not stop the application]]
  def encryption_settings_with(env)
    script = <<~RUBY
      require "./config/application"
      encryption = SwayRails::Application.config.active_record.encryption
      print [
        encryption[:primary_key],
        encryption[:deterministic_key],
        encryption[:key_derivation_salt]
      ].inspect
    RUBY

    full_env = env.merge("RAILS_ENV" => "test", "SWAY_ALLOW_HOST_RAILS" => "1")
    stdout, stderr, status =
      Bundler.with_unbundled_env do
        Open3.capture3(full_env, "ruby", "-e", script, chdir: Rails.root.to_s)
      end

    [stdout, status.exitstatus, stderr]
  end

  describe "reading the keys from the environment" do
    it "boots with none of the three set and leaves every key unconfigured" do
      output, status, errors = encryption_settings_with(key_names.to_h { |name| [name, nil] })

      expect(status).to eq(0),
        "config/application.rb must load with no encryption keys present, so a " \
        "worktree and a fresh clone can still boot. Output: #{output}#{errors}"
      expect(output).to eq([nil, nil, nil].inspect)
    end

    it "carries all three through, stripped of surrounding whitespace" do
      output, status, errors = encryption_settings_with(
        "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => "primary\n",
        "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY" => "deterministic\n",
        "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT" => "  salt  "
      )

      expect(status).to eq(0), "Output: #{output}#{errors}"
      expect(output).to eq(%w[primary deterministic salt].inspect)
    end

    it "treats a whitespace-only key as absent rather than as a real key" do
      output, status, errors = encryption_settings_with(key_names.to_h { |name| [name, " \n"] })

      expect(status).to eq(0), "Output: #{output}#{errors}"
      expect(output).to eq([nil, nil, nil].inspect)
    end
  end

  describe "the running application" do
    it "has booted without any of the three keys in its own environment" do
      expect(key_names.map { |name| ENV.fetch(name, nil) }).to all(be_blank)
      expect(Rails.application.initialized?).to be(true)
    end

    # @lat: [[active-record-encryption-keys#Test environment keys]]
    it "has config/environments/test.rb's fixed keys, with none set in the environment" do
      expect(ActiveRecord::Encryption.config.primary_key).to eq("test-primary-key-not-a-real-secret")
      expect(ActiveRecord::Encryption.config.deterministic_key).to eq("test-deterministic-key-not-a-real-secret")
      expect(ActiveRecord::Encryption.config.key_derivation_salt).to eq("test-key-derivation-salt-not-a-real-secret")
    end
  end

  describe "the development environment's own keys" do
    let(:development_config) { Rails.root.join("config", "environments", "development.rb").read }
    let(:settings) { %w[primary_key deterministic_key key_derivation_salt] }

    it "assigns all three, so a fresh clone boots with encrypted columns" do
      settings.each do |setting|
        expect(development_config).to match(/^\s*config\.active_record\.encryption\.#{setting} = "/),
          "config/environments/development.rb does not set #{setting}, so reading it raises " \
          "ActiveRecord::Encryption::Errors::Configuration and development stops at the first " \
          "encrypted column"
      end
    end

    it "uses values that announce themselves as fake" do
      assigned = development_config.scan(/^\s*config\.active_record\.encryption\.\w+ = "([^"]+)"/).flatten

      expect(assigned.length).to eq(3)
      expect(assigned).to all(include("not-a-real-secret"))
    end
  end

  describe "delivery to production" do
    let(:secrets_common) { Rails.root.join(".kamal", "secrets-common").read }
    let(:deploy_config) do
      YAML.load(ERB.new(Rails.root.join("config", "deploy.yml").read).result, aliases: true)
    end

    it "fetches each key from the vault and assigns it in .kamal/secrets-common" do
      key_names.each do |name|
        expect(secrets_common).to include("#{name}=$(kamal secrets extract #{name} $SECRETS)"),
          "#{name} has no extract line in .kamal/secrets-common"
        expect(secrets_common[/^SECRETS=.*$/].to_s).to include(name),
          "#{name} is not in the `kamal secrets fetch` list, so the extract above finds nothing"
      end
    end

    it "lists each key under env.secret in config/deploy.yml" do
      expect(deploy_config.dig("env", "secret")).to include(*key_names)
    end

    it "holds no key value in .kamal/secrets-common" do
      key_names.each do |name|
        expect(secrets_common).not_to match(/^#{name}=(?!\$\()/)
      end
    end
  end

  describe "encrypting a column with the test environment's own keys" do
    # @lat: [[active-record-encryption-keys#Test environment keys]]
    it "round-trips a scrambled value with no environment variable set" do
      # An anonymous ActiveRecord subclass; the type checker reads the Class.new body as Object.
      scrambled_model = Class.new(ApplicationRecord) do
        self.table_name = "categories" # steep:ignore
        encrypts :name # steep:ignore
      end

      plaintext = "encryption-roundtrip-#{SecureRandom.hex(8)}"
      record = scrambled_model.create!(name: plaintext, slug: "encryption-roundtrip-#{SecureRandom.hex(8)}") # steep:ignore

      expect(scrambled_model.find(record.id).name).to eq(plaintext)

      stored_value = ActiveRecord::Base.connection.select_value(
        "SELECT name FROM categories WHERE id = #{record.id}"
      )
      expect(stored_value).not_to eq(plaintext)
    end
  end
end
