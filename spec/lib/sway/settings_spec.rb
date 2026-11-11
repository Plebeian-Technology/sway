# frozen_string_literal: true

require "rails_helper"
require "prism"
require "yaml"

# @lat: [[steep-typed-spec-helpers#let and def inside a describe block]]
# Every group's plan adds its own names to DECLARED_NAMES -- the one this phase's enumeration exists to produce.
module SettingsSpecHelpers
  DECLARED_NAMES = %w[
    LEGISTAR_API_BASE_URL
    LAW_XML_GITHUB_BASE_URL
    OPEN_BALTIMORE_ARCGIS_BASE_URL
    WIKIDATA_SPARQL_BASE_URL
    NOMINATIM_API_BASE_URL
    OPENSTATES_API_BASE_URL
    CONGRESS_GOV_API_BASE_URL
    CONGRESS_LEGISLATORS_BASE_URL
    OPEN_LEGISLATOR_BASE_URL
    BRAVE_SEARCH_API_BASE_URL
    RATE_LIMIT_SIGN_IN_ENABLED
    RATE_LIMIT_SIGN_UP_ENABLED
    RATE_LIMIT_PHONE_VERIFY_ENABLED
    RATE_LIMIT_EMAIL_VERIFY_ENABLED
    RATE_LIMIT_LEGISLATOR_EMAIL_ENABLED
    RATE_LIMIT_CSP_REPORT_ENABLED
    RATE_LIMIT_ORG_INVITE_ENABLED
    RATE_LIMIT_DEVICE_PUSH_TOKEN_ENABLED
    RATE_LIMIT_BOOTSTRAP_ENABLED
    RATE_LIMIT_PREFERENCES_ENABLED
    RATE_LIMIT_BILL_SUMMARY_REPORT_ENABLED
    LEGISLATION_ROOT
    LEGISLATION_BILLS_RAW_ROOT
    LEGISLATION_BILLS_TEXT_ROOT
    LEGISLATION_HEARINGS_ROOT
    LEGISLATION_LAW_ROOT
    LEGISLATION_DIFFS_ROOT
    LEGISLATION_ATTACHMENTS_ROOT
    LEGISLATION_PROMPT_DUMPS_ROOT
    TESSDATA_PREFIX
    PDF_EXTRACTOR_URL
    LLM_PROVIDER
    LLAMACPP_MODEL
    LLAMACPP_BASE_URL
    OPENROUTER_BASE_URL
    LLM_LLAMACPP_THINKING
    LLM_REQUEST_TIMEOUT_SECONDS
    OPENROUTER_REQUEST_TIMEOUT_SECONDS
    LLM_MAX_SOURCE_CHARS
    LLM_MAX_TESTIMONY_TOKENS
    LLM_MAX_TESTIMONY_CHARS
    LLM_MAX_SUMMARY_CONTEXT_CHARS
    LLM_MAX_POSITIONS_CHUNKS
    SKIP_PHONE_VERIFICATION
    DEV_ACCOUNT_FULL_NAME
    DEV_ACCOUNT_SWAY_LOCALE
    APPLE_APP_STORE_ID
    MOBILE_MIN_VERSION
    MOBILE_LATEST_VERSION
    ANDROID_CERT_SHA256_FINGERPRINTS
    APPLE_TEAM_ID
    APPLE_BUNDLE_ID
    APP_ASSOCIATION_HOSTS
    INBOUND_SMS_FORWARD_TO
    ALLOW_NONPRODUCTION_SMS
    SWAY_DEPLOYED_AT
    SWAY_SKIP_DB_BACKUP
    IS_DOCKER
    DEV_TUNNEL_HOST
    BESZEL_URL
    BESZEL_ADMIN_EMAIL_DOMAINS
    WEBAUTHN_ALLOWED_ORIGINS
    WEBAUTHN_RELATED_HOSTS
    WEBAUTHN_RP_ID
  ].freeze

  # @lat: [[settings-spec-test-design#Why EXPECTED_PREFIXES exists]]
  EXPECTED_PREFIXES = {
    upstream: "",
    rate_limits: "RATE_LIMIT",
    legislation: "",
    llm: "",
    dev_login: "",
    mobile: "",
    ops: "",
    webauthn: "WEBAUTHN"
  }.freeze

  # A complete, valid set of the two DEV_ACCOUNT_* values.
  VALID_DEV_ACCOUNT_ENV = {
    "DEV_ACCOUNT_FULL_NAME" => "Skip Flow User",
    "DEV_ACCOUNT_SWAY_LOCALE" => "cambridge-massachusetts-united_states"
  }.freeze

  # One env-readable string per registered caster, and what reading it back
  # casts to. Lets the binding check (trap three) probe any attribute
  # regardless of its declared type, so a later group with a non-string
  # attribute is covered with no edit here.
  PROBE_VALUE_BY_TYPE = {
    :string => ["a probed value", "a probed value"],
    :integer => ["424242", 424242],
    :integer! => ["424242", 424242],
    :float => ["42.42", 42.42],
    :float! => ["42.42", 42.42],
    :boolean => ["true", true],
    # mobile's android_cert_sha256_fingerprints -- the only attribute in the
    # phase declared with the array: true, type: :string coerce_types shape
    # rather than a plain caster symbol (needed so to_rbs generates
    # Array[String] rather than untyped -- see 68-08-SUMMARY.md).
    {array: true, type: :string} => ["AA:BB:CC, DD:EE:FF", %w[AA:BB:CC DD:EE:FF]]
  }.freeze #: Hash[Symbol | Hash[Symbol, bool | Symbol], [String, untyped]]

  # klass's own declared prefix, joined to attribute's upper-case name --
  # the same derivation "the enumeration" describe block below uses, so the
  # two cannot drift apart.
  def self.env_var_name(klass, attribute)
    [klass.env_prefix, attribute.to_s.upcase].reject(&:empty?).join("_")
  end

  # @lat: [[settings-spec-test-design#Why attributes_without_declared_type exists]]
  def self.attributes_without_declared_type(klass)
    (klass.config_attributes || []).reject { |attribute| (klass.coercion_mapping || {}).key?(attribute) }
  end

  # The raw string to write, and the value reading it back should produce,
  # for whatever type `attribute` declares.
  def self.probe_pair_for(klass, attribute)
    type = (klass.coercion_mapping || {}).fetch(attribute)
    PROBE_VALUE_BY_TYPE.fetch(type) do
      raise "No probe value registered for #{klass}##{attribute}'s declared type " \
        "#{type.inspect} -- add one to SettingsSpecHelpers::PROBE_VALUE_BY_TYPE"
    end
  end

  # @lat: [[settings-spec-test-design#Why companion_env_for exists]]
  def self.companion_env_for(klass, attribute)
    klass.required_attributes.each_with_object({}) do |required_name, env|
      required_attribute = required_name.to_sym
      next if required_attribute == attribute
      next unless klass.defaults[required_name.to_s].nil?

      raw, = probe_pair_for(klass, required_attribute)
      env[env_var_name(klass, required_attribute)] = raw
    end
  end

  # @lat: [[settings-spec-test-design#The three anyway_config traps]]
  # @lat: [[steep-typed-spec-helpers#Class.new(SomeBase) do ... end]]

  # The only shape where auto-cast on vs off (disable_auto_cast!) differs:
  # an attribute with no coerce_types entry routes through the fallback
  # caster, where a declared type never does (measured against
  # Anyway::TypeCaster#coerce).
  class NoTypeProbe < Sway::Settings::Base
    config_name "settings_spec_probe_no_type"
    env_prefix ""
    attr_config bare_number: nil
  end

  # Never calls env_prefix itself -- the exact shape spike3.rb measured:
  # the gem falls back to config_name.upcase, binding target_name to
  # SETTINGS_SPEC_PROBE_WRONG_PREFIX_TARGET_NAME rather than the bare
  # TARGET_NAME a caller would expect.
  class WrongPrefixProbe < Sway::Settings::Base
    config_name "settings_spec_probe_wrong_prefix"
    attr_config target_name: "default_value"
    coerce_types target_name: :string
  end

  # One required attribute with no default -- the only shape that can make
  # build! collect a genuine validation failure (the kill-switch example;
  # every real attribute in this plan carries a default, so none of them
  # can go missing on their own).
  class MissingRequiredProbe < Sway::Settings::Base
    config_name "settings_spec_probe_missing_required"
    env_prefix ""
    attr_config required_name: nil
    coerce_types required_name: :string
    required :required_name
  end

  # One whole-number attribute -- no registered group declares :integer
  # today, so the unreadable-text example needs its own.
  class IntegerProbe < Sway::Settings::Base
    config_name "settings_spec_probe_integer"
    env_prefix ""
    attr_config whole_number: nil
    coerce_types whole_number: :integer
  end

  # @lat: [[settings-spec-test-design#Why the settings-setter-write guard walks Prism instead of matching text]]
  class FloatProbe < Sway::Settings::Base
    config_name "settings_spec_probe_float"
    env_prefix ""
    attr_config decimal_number: nil
    coerce_types decimal_number: :float
  end

  # @lat: [[settings-spec-test-design#Why the settings-setter-write guard walks Prism instead of matching text]]
  class SettingsSetterVisitor < Prism::Visitor
    # @lat: [[steep-typed-spec-helpers#let and def inside a describe block#Accepting the gap with steep:ignore instead of moving the helper out]]
    class SettingsWrite
      attr_reader :path, :line, :method

      def initialize(path:, line:, method:)
        @path = path
        @line = line
        @method = method
      end

      def to_s
        "#{path}:#{line} writes #{method} on a chain rooted at Sway::Settings"
      end
    end

    attr_reader :findings

    def initialize(path)
      super()
      @path = path
      @findings = []
    end

    def visit_call_node(node)
      if node.attribute_write? && rooted_at_sway_settings?(node.receiver)
        @findings << SettingsWrite.new(path: @path, line: node.location.start_line, method: node.name.to_s)
      end

      super
    end

    private

    # attribute_write? already excludes comparison operators (==, <=, ...)
    # -- Prism only sets the flag for genuine `receiver.name = value` calls,
    # measured against a planted `Sway::Settings.upstream.x == "y"` line.
    def rooted_at_sway_settings?(node)
      base = base_receiver(node)
      return false if base.nil?

      text = base.slice
      text == "Sway::Settings" || text.start_with?("Sway::Settings::")
    end

    # Walks down a call chain's own receivers (`a.b.c` -> `a.b` -> `a`)
    # until it reaches something that is not itself a call -- the root the
    # whole chain is written against.
    def base_receiver(node)
      return node unless node.is_a?(Prism::CallNode)

      receiver = node.receiver
      return nil if receiver.nil?

      base_receiver(receiver)
    end
  end

  # @lat: [[settings-spec-test-design#Why the settings-setter-write guard walks Prism instead of matching text]]
  ALLOWED_SETTINGS_WRITE_PATHS = ["lib/sway/settings.rb"].freeze
  ALLOWED_SETTINGS_WRITE_PREFIXES = ["lib/sway/settings/"].freeze

  # git ls-files, matching EnvCredentialScanner#scannable_paths -- an
  # untracked scratch file cannot fail this check either.
  def self.tracked_ruby_files
    `git ls-files -z -- '*.rb'`.split("\0").reject do |path|
      ALLOWED_SETTINGS_WRITE_PATHS.include?(path) ||
        ALLOWED_SETTINGS_WRITE_PREFIXES.any? { |prefix| path.start_with?(prefix) } ||
        !File.file?(path)
    end
  end

  def self.settings_setter_findings(paths)
    paths.flat_map do |path|
      visitor = SettingsSetterVisitor.new(path)
      Prism.parse(File.read(path)).value.accept(visitor)
      visitor.findings
    end
  end

  # @lat: [[steep-typed-spec-helpers#let and def inside a describe block]]
  def self.deploy_clear_env
    @deploy_clear_env ||= YAML.load_file(Rails.root.join("config", "deploy.yml")).fetch("env").fetch("clear")
  end
end

# @lat: [[settings-spec-test-design#Why "the enumeration" is a check, not a note]]
RSpec.describe Sway::Settings do
  describe "the enumeration" do
    it "lists every declared environment name" do
      expect(SettingsSpecHelpers::DECLARED_NAMES).to contain_exactly(
        "LEGISTAR_API_BASE_URL",
        "LAW_XML_GITHUB_BASE_URL",
        "OPEN_BALTIMORE_ARCGIS_BASE_URL",
        "NOMINATIM_API_BASE_URL",
        "WIKIDATA_SPARQL_BASE_URL",
        "OPENSTATES_API_BASE_URL",
        "CONGRESS_GOV_API_BASE_URL",
        "CONGRESS_LEGISLATORS_BASE_URL",
        "OPEN_LEGISLATOR_BASE_URL",
        "BRAVE_SEARCH_API_BASE_URL",
        "RATE_LIMIT_SIGN_IN_ENABLED",
        "RATE_LIMIT_SIGN_UP_ENABLED",
        "RATE_LIMIT_PHONE_VERIFY_ENABLED",
        "RATE_LIMIT_EMAIL_VERIFY_ENABLED",
        "RATE_LIMIT_LEGISLATOR_EMAIL_ENABLED",
        "RATE_LIMIT_CSP_REPORT_ENABLED",
        "RATE_LIMIT_ORG_INVITE_ENABLED",
        "RATE_LIMIT_DEVICE_PUSH_TOKEN_ENABLED",
        "RATE_LIMIT_BOOTSTRAP_ENABLED",
        "RATE_LIMIT_PREFERENCES_ENABLED",
        "RATE_LIMIT_BILL_SUMMARY_REPORT_ENABLED",
        "LEGISLATION_ROOT",
        "LEGISLATION_BILLS_RAW_ROOT",
        "LEGISLATION_BILLS_TEXT_ROOT",
        "LEGISLATION_HEARINGS_ROOT",
        "LEGISLATION_LAW_ROOT",
        "LEGISLATION_DIFFS_ROOT",
        "LEGISLATION_ATTACHMENTS_ROOT",
        "LEGISLATION_PROMPT_DUMPS_ROOT",
        "TESSDATA_PREFIX",
        "PDF_EXTRACTOR_URL",
        "LLM_PROVIDER",
        "LLAMACPP_MODEL",
        "LLAMACPP_BASE_URL",
        "OPENROUTER_BASE_URL",
        "LLM_LLAMACPP_THINKING",
        "LLM_REQUEST_TIMEOUT_SECONDS",
        "OPENROUTER_REQUEST_TIMEOUT_SECONDS",
        "LLM_MAX_SOURCE_CHARS",
        "LLM_MAX_TESTIMONY_TOKENS",
        "LLM_MAX_TESTIMONY_CHARS",
        "LLM_MAX_SUMMARY_CONTEXT_CHARS",
        "LLM_MAX_POSITIONS_CHUNKS",
        "SKIP_PHONE_VERIFICATION",
        "DEV_ACCOUNT_FULL_NAME",
        "DEV_ACCOUNT_SWAY_LOCALE",
        "APPLE_APP_STORE_ID",
        "MOBILE_MIN_VERSION",
        "MOBILE_LATEST_VERSION",
        "ANDROID_CERT_SHA256_FINGERPRINTS",
        "APPLE_TEAM_ID",
        "APPLE_BUNDLE_ID",
        "APP_ASSOCIATION_HOSTS",
        "INBOUND_SMS_FORWARD_TO",
        "ALLOW_NONPRODUCTION_SMS",
        "SWAY_DEPLOYED_AT",
        "SWAY_SKIP_DB_BACKUP",
        "IS_DOCKER",
        "DEV_TUNNEL_HOST",
        "BESZEL_URL",
        "BESZEL_ADMIN_EMAIL_DOMAINS",
        "WEBAUTHN_ALLOWED_ORIGINS",
        "WEBAUTHN_RELATED_HOSTS",
        "WEBAUTHN_RP_ID"
      )
    end

    # The check: for every registered group class, its declared env_prefix
    # joined to each attribute name in upper case must equal the frozen
    # list above -- exactly, in both directions. This is where every later
    # group's plan adds its names.
    it "equals the set derived from every registered group class" do
      derived = Sway::Settings::GROUPS.each_value.flat_map do |klass|
        prefix = klass.env_prefix
        (klass.config_attributes || []).map do |attribute|
          [prefix, attribute.to_s.upcase].reject(&:empty?).join("_")
        end
      end

      expect(derived).to contain_exactly(*SettingsSpecHelpers::DECLARED_NAMES)
    end
  end

  describe "every group class" do
    it "declares its own env_prefix explicitly rather than inheriting one" do
      Sway::Settings::GROUPS.each_value do |klass|
        expect(klass.instance_variable_defined?(:@env_prefix)).to be(true),
          "#{klass} does not call env_prefix in its own body"
      end
    end

    it "disables automatic casting, through the shared base class" do
      Sway::Settings::GROUPS.each_value do |klass|
        expect(klass.ancestors).to include(Sway::Settings::Base)
      end
    end

    it "declares a type for every attribute" do
      Sway::Settings::GROUPS.each_value do |klass|
        (klass.config_attributes || []).each do |attribute|
          expect(klass.coercion_mapping).to have_key(attribute),
            "#{klass}##{attribute} has no declared coerce_types entry"
        end
      end
    end
  end

  # @lat: [[settings-spec-test-design#The three anyway_config traps]]
  describe "trap one: automatic casting" do
    it "disables automatic casting and declares a type for every attribute -- the same check a probe class with an undeclared attribute fails" do
      Sway::Settings::GROUPS.each_value do |klass|
        expect(klass.fallback_type_caster).to eq(Anyway::NoCast)
        expect(SettingsSpecHelpers.attributes_without_declared_type(klass)).to be_empty
      end

      expect(SettingsSpecHelpers.attributes_without_declared_type(SettingsSpecHelpers::NoTypeProbe))
        .to eq([:bare_number])
    end

    it "keeps a numeric-looking string and a comma-separated value as plain text for a declared :string attribute" do
      with_env("LEGISTAR_API_BASE_URL" => "6444444444,0987654321") do
        instance = Sway::Settings::Upstream.new

        expect(instance.legistar_api_base_url).to eq("6444444444,0987654321")
        expect(instance.legistar_api_base_url).to be_a(String)
      end
    end

    it "keeps a value with no declared type as text -- would read it as an Integer if disable_auto_cast! were ever reverted" do
      with_env("BARE_NUMBER" => "6444444444") do
        instance = SettingsSpecHelpers::NoTypeProbe.new

        expect(instance.bare_number).to eq("6444444444")
        expect(instance.bare_number).to be_a(String)
      end
    end

    # Every group is a plain attribute reader (attr_config), never
    # Rails' OrderedOptions -- OrderedOptions answers nil for an unknown key
    # instead of raising, which would turn a misspelled setting name into a
    # silent nil read instead of a boot-time NoMethodError.
    it "raises NoMethodError, not a silent nil, for an attribute no group declares" do
      Sway::Settings::GROUPS.each_value do |klass|
        instance = klass.allocate

        expect { instance.this_attribute_does_not_exist }.to raise_error(NoMethodError),
          "#{klass} answered something other than NoMethodError for an undeclared attribute"
      end
    end
  end

  # The second measured hazard: a blank env value beats a declared
  # default, and the collision with it -- the gem's own required check runs before a
  # subclass's on_load repair unless the base class moves it.
  describe "trap two: a blank value counts as absent" do
    it "repairs a blank or whitespace-only value back to the declared default, for every attribute that has one" do
      Sway::Settings::GROUPS.each_value do |klass|
        klass.defaults.each do |raw_name, default_value|
          attribute = raw_name.to_sym

          # An attribute with a nil default AND required has no default to
          # repair TO -- that combination means "refuse when blank", tested
          # on its own group's describe block (dev_login's seven), not here.
          next if default_value.nil? && klass.required_attributes.map(&:to_s).include?(raw_name)

          env_name = SettingsSpecHelpers.env_var_name(klass, attribute)
          companion = SettingsSpecHelpers.companion_env_for(klass, attribute)

          ["", "   "].each do |blank_value|
            with_env(companion.merge(env_name => blank_value)) do
              instance = klass.new

              expect(instance.public_send(attribute)).to eq(default_value),
                "#{klass}##{attribute} did not repair #{env_name}=#{blank_value.inspect} back to its default"
            end
          end
        end
      end
    end

    it "runs the blank repair before the gem's own required check in the base class's load callbacks" do
      callbacks = Sway::Settings::Base.load_callbacks
      repair_index = callbacks.index { |callback| callback.is_a?(Anyway::Config::BlockCallback) }
      required_index = callbacks.index do |callback|
        callback.is_a?(Anyway::Config::NamedCallback) && callback.name == :validate_required_attributes!
      end

      expect(repair_index).not_to be_nil, "no on_load block callback found -- has the blank repair moved?"
      expect(required_index).not_to be_nil, "no validate_required_attributes! callback found -- has the gem renamed it?"
      expect(repair_index).to be < required_index
    end
  end

  # The fourth measured hazard: a base class that inherits its prefix
  # binds silently to nothing. SettingsSpecHelpers.probe_pair_for
  # generalises the check across whatever type a later group declares.
  describe "trap three: binding to the right environment name" do
    it "binds every attribute to the environment name its class's prefix and its own name derive -- the same check a probe class with an unbound prefix fails" do
      Sway::Settings::GROUPS.each_value do |klass|
        klass.config_attributes.to_a.each do |attribute|
          env_name = SettingsSpecHelpers.env_var_name(klass, attribute)
          raw, expected = SettingsSpecHelpers.probe_pair_for(klass, attribute)
          companion = SettingsSpecHelpers.companion_env_for(klass, attribute)

          with_env(companion.merge(env_name => raw)) do
            instance = klass.new

            expect(instance.public_send(attribute)).to eq(expected),
              "#{klass}##{attribute} did not bind to #{env_name}"
          end
        end
      end

      with_env("TARGET_NAME" => "a value nobody should read back") do
        instance = SettingsSpecHelpers::WrongPrefixProbe.new

        expect(instance.target_name).to eq("default_value")
      end
    end

    it "declares its prefix explicitly, matching what each registered group is expected to declare" do
      Sway::Settings::GROUPS.each do |name, klass|
        expected = SettingsSpecHelpers::EXPECTED_PREFIXES.fetch(name) do
          raise "#{name} is registered in Sway::Settings::GROUPS with no entry in " \
            "SettingsSpecHelpers::EXPECTED_PREFIXES -- add one"
        end

        expect(klass.env_prefix).to eq(expected)
      end
    end
  end

  # @lat: [[settings-build-suppress-validations#Why the kill-switch spec sets Anyway::Settings.suppress_required_validations directly, not just through with_env]]
  describe "the kill switch" do
    it "still refuses to build when ANYWAY_SUPPRESS_VALIDATIONS is set, because build! pins the flag off unless SECRET_KEY_BASE_DUMMY is set" do
      original = Anyway::Settings.suppress_required_validations

      # @lat: [[settings-build-suppress-validations#Why the kill-switch spec sets Anyway::Settings.suppress_required_validations directly, not just through with_env]]
      begin
        with_env("ANYWAY_SUPPRESS_VALIDATIONS" => "1", "SECRET_KEY_BASE_DUMMY" => nil) do
          Anyway::Settings.suppress_required_validations = true

          stub_const("Sway::Settings::GROUPS", {probed: SettingsSpecHelpers::MissingRequiredProbe})

          expect { Sway::Settings.build! }.to raise_error(Sway::Settings::MissingValues)
        end
      ensure
        # Process-global: leaking `true` here would silently disable required
        # validation for every example that runs after this one.
        Anyway::Settings.suppress_required_validations = original
      end
    end

    # @lat: [[settings-build-suppress-validations#Why the kill-switch spec sets Anyway::Settings.suppress_required_validations directly, not just through with_env]]
    # Pinning against ANYWAY_SUPPRESS_VALIDATIONS must not also pin against SECRET_KEY_BASE_DUMMY.
    it "leaves validation suppressed when SECRET_KEY_BASE_DUMMY is set, the Docker image build case" do
      original = Anyway::Settings.suppress_required_validations

      begin
        with_env("SECRET_KEY_BASE_DUMMY" => "1", "ANYWAY_SUPPRESS_VALIDATIONS" => nil) do
          stub_const("Sway::Settings::GROUPS", {probed: SettingsSpecHelpers::MissingRequiredProbe})

          expect { Sway::Settings.build! }.not_to raise_error
        end
      ensure
        Anyway::Settings.suppress_required_validations = original
      end
    end
  end

  # Text becomes a real value in the declaration, and unreadable text
  # refuses the boot rather than becoming zero. No registered group
  # declares :integer today, so this needs its own probe.
  describe "unreadable text" do
    it "raises on a whole number that is not a whole number, naming the value's type rather than answering zero" do
      with_env("WHOLE_NUMBER" => "lots") do
        expect { SettingsSpecHelpers::IntegerProbe.new }.to raise_error(ArgumentError, /Integer/)
      end
    end

    # @lat: [[settings-type-caster-design#Integer: base 10, explicitly]]
    it "reads a leading-zero whole number as decimal, not octal" do
      with_env("WHOLE_NUMBER" => "030") do
        expect(SettingsSpecHelpers::IntegerProbe.new.whole_number).to eq(30)
      end
    end

    it "refuses a hex-prefixed whole number rather than reading it as hex" do
      with_env("WHOLE_NUMBER" => "0x10") do
        expect { SettingsSpecHelpers::IntegerProbe.new }.to raise_error(ArgumentError, /Integer/)
      end
    end

    it "reads a leading-zero number invalid as octal as its decimal value, rather than raising" do
      # @lat: [[settings-type-caster-design#Integer: base 10, explicitly]]
      with_env("WHOLE_NUMBER" => "090") do
        expect(SettingsSpecHelpers::IntegerProbe.new.whole_number).to eq(90)
      end
    end

    it "reads a leading-zero decimal number as base 10, not octal" do
      with_env("DECIMAL_NUMBER" => "030.5") do
        expect(SettingsSpecHelpers::FloatProbe.new.decimal_number).to eq(30.5)
      end
    end

    it "refuses a hex-prefixed decimal number rather than reading it as hex" do
      with_env("DECIMAL_NUMBER" => "0x10") do
        expect { SettingsSpecHelpers::FloatProbe.new }.to raise_error(ArgumentError, /invalid value for Float/)
      end
    end
  end

  # The ordering is load-bearing, not decoration. config/environments/
  # test.rb writes into the environment during load_environment_config, so
  # assembling any earlier would read a different world.
  describe "the assembly point" do
    it "assembles sway.settings after load_environment_config in the application's initializer list" do
      names = Rails.application.initializers.tsort.map(&:name)
      # Rails::Initializable stores a name exactly as given to `initializer` --
      # our own call passes a String ("sway.settings"), the railtie's own
      # :load_environment_config is a Symbol. Comparing the wrong types would
      # silently never find either and both index calls would return nil.
      settings_index = names.index("sway.settings")
      env_config_index = names.index(:load_environment_config)

      expect(settings_index).not_to be_nil, "no initializer named sway.settings was found"
      expect(env_config_index).not_to be_nil, "no initializer named load_environment_config was found"
      expect(settings_index).to be > env_config_index
    end
  end

  # The lost property: a config object accepts a write even after
  # freeze, and the generated signature declares a setter for every
  # attribute, so a write at a call site type-checks. This is the only
  # thing standing between a call site and a silent write (T-68-05).
  describe "no settings-setter call outside lib/sway/settings/" do
    it "reports zero settings-setter findings across the real tracked tree" do
      findings = SettingsSpecHelpers.settings_setter_findings(SettingsSpecHelpers.tracked_ruby_files)

      expect(findings).to be_empty, findings.join("\n")
    end

    it "finds a planted settings setter and ignores the same words in a comment and a string literal" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "planted_settings_write.rb")
        File.write(path, <<~RUBY)
          # Sway::Settings.upstream.legistar_api_base_url = "not a call" -- a comment
          PLANTED_LOOK_ALIKE = "Sway::Settings.upstream.legistar_api_base_url = 'not a call either'"

          Sway::Settings.upstream.legistar_api_base_url = "https://evil.example"
        RUBY

        findings = SettingsSpecHelpers.settings_setter_findings([path])

        expect(findings.length).to eq(1)
        expect(findings.first.line).to eq(4)
        expect(findings.first.method).to eq("legistar_api_base_url=")
      end
    end
  end

  # @lat: [[settings-spec-test-design#Why LEGISLATION_ROOT and LLM_PROVIDER are pinned against config/deploy.yml directly]]
  describe "pinned against config/deploy.yml -- the two names production actually sets" do
    it "reads LEGISLATION_ROOT and LLM_PROVIDER back through their settings readers, set to the deploy file's own values" do
      clear = SettingsSpecHelpers.deploy_clear_env

      with_env("LEGISLATION_ROOT" => clear.fetch("LEGISLATION_ROOT")) do
        expect(Sway::Settings::Legislation.new.legislation_root).to eq(clear.fetch("LEGISLATION_ROOT"))
      end

      with_env("LLM_PROVIDER" => clear.fetch("LLM_PROVIDER")) do
        expect(Sway::Settings::Llm.new.llm_provider).to eq(clear.fetch("LLM_PROVIDER"))
      end
    end

    # @lat: [[settings-spec-test-design#Why LEGISLATION_ROOT and LLM_PROVIDER are pinned against config/deploy.yml directly]]
    it "declares a default that differs from what the deploy file sets, for both names" do
      clear = SettingsSpecHelpers.deploy_clear_env

      expect(Sway::Settings::Legislation.new.legislation_root).to be_nil
      expect(clear.fetch("LEGISLATION_ROOT")).not_to be_nil

      expect(Sway::Settings::Llm.new.llm_provider).to eq("llamacpp")
      expect(clear.fetch("LLM_PROVIDER")).to eq("claude")
    end
  end

  # @lat: [[rate-limit-kill-switches#Why the typo guard reads the raw env value]]
  describe "Sway::Settings::RateLimits" do
    it "refuses to build rather than silently disable a throttle on a typo'd value" do
      with_env("RATE_LIMIT_SIGN_IN_ENABLED" => "ture") do
        expect { Sway::Settings::RateLimits.new }
          .to raise_error(ArgumentError, /RATE_LIMIT_SIGN_IN_ENABLED.*not a yes-or-no value/)
      end
    end

    it "still reads true (protected) for every recognized truthy word" do
      %w[true yes y 1 t TRUE Yes Y].each do |raw|
        with_env("RATE_LIMIT_SIGN_IN_ENABLED" => raw) do
          expect(Sway::Settings::RateLimits.new.sign_in_enabled).to eq(true),
            "RATE_LIMIT_SIGN_IN_ENABLED=#{raw.inspect} did not read as enabled"
        end
      end
    end

    it "reads false (opted out) for every recognized false-word, not just true or unset" do
      %w[false no n 0 f].each do |raw|
        with_env("RATE_LIMIT_SIGN_IN_ENABLED" => raw) do
          expect(Sway::Settings::RateLimits.new.sign_in_enabled).to eq(false),
            "RATE_LIMIT_SIGN_IN_ENABLED=#{raw.inspect} did not read as disabled"
        end
      end
    end

    it "falls back to the true default when unset or blank" do
      [nil, "", "   "].each do |raw|
        with_env("RATE_LIMIT_SIGN_IN_ENABLED" => raw) do
          expect(Sway::Settings::RateLimits.new.sign_in_enabled).to eq(true),
            "RATE_LIMIT_SIGN_IN_ENABLED=#{raw.inspect} did not fall back to the default"
        end
      end
    end
  end

  # @lat: [[llm-settings-group-design#Why the "every reader defaults" spec forces llm_request_timeout_seconds: nil]]
  describe "Sway::Settings::Llm" do
    # @lat: [[llm-settings-group-design#Why the "every reader defaults" spec forces llm_request_timeout_seconds: nil]]
    it "defaults every one of its ten readers when unset, in the test environment" do
      instance = Sway::Settings::Llm.new(llm_request_timeout_seconds: nil)

      expect(instance.llm_provider).to eq("llamacpp")
      expect(instance.llamacpp_model).to eq("local")
      expect(instance.llamacpp_base_url).to eq("http://host.docker.internal:8888/v1")
      expect(instance.llm_llamacpp_thinking).to eq(false)
      expect(instance.llm_request_timeout_seconds).to eq(120)
      expect(instance.llm_max_source_chars).to eq(300_000)
      expect(instance.llm_max_testimony_tokens).to eq(90_000)
      expect(instance.llm_max_testimony_chars).to eq(150_000)
      expect(instance.llm_max_summary_context_chars).to eq(4_000)
      expect(instance.llm_max_positions_chunks).to eq(10)
    end

    # @lat: [[llm-settings-group-design#The Rails.env.development? class-body timing]]
    it "reads the non-development default for the three caps that differ in development" do
      instance = Sway::Settings::Llm.new

      expect(instance.llm_max_source_chars).to eq(300_000)
      expect(instance.llm_max_testimony_tokens).to eq(90_000)
      expect(instance.llm_max_testimony_chars).to eq(150_000)
    end

    it "raises on a whole-number cap given text that is not a whole number, naming the value's type rather than answering zero" do
      with_env("LLM_REQUEST_TIMEOUT_SECONDS" => "lots") do
        expect { Sway::Settings::Llm.new }.to raise_error(ArgumentError, /Integer/)
      end
    end

    # @lat: [[settings-spec-test-design#Why the LLM group's boot-path example duplicates a generic one]]
    it "raises through Sway::Settings.build!, the boot path, rather than silently building a cap of zero" do
      with_env("LLM_MAX_TESTIMONY_TOKENS" => "lots") do
        expect { Sway::Settings.build! }.to raise_error(Sway::Settings::MissingValues, /llm/)
      end
    end
  end

  # @lat: [[settings-group-declaration-notes#Why dev_account_full_name (and its siblings) have a real default]]
  describe "Sway::Settings::DevLogin" do
    describe "the phone-check-skip switch" do
      it "reads true in a local environment when set" do
        expect(Sway::Settings::DevLogin.new(skip_phone_verification: true).skip_phone_verification).to be(true)
      end

      it "reads false outside a local environment even when set, so no deployed value can turn the check off" do
        allow(Rails.env).to receive(:local?).and_return(false)

        instance = Sway::Settings::DevLogin.new(skip_phone_verification: true)

        expect(instance.skip_phone_verification).to be(false)
        expect(instance.skip_phone_verification?).to be(false)
      end
    end

    describe "the two stand-in account values" do
      it "builds and every reader returns its value, with both set in the test environment" do
        with_env(SettingsSpecHelpers::VALID_DEV_ACCOUNT_ENV) do
          instance = Sway::Settings::DevLogin.new

          expect(instance.dev_account_full_name).to eq("Skip Flow User")
          expect(instance.dev_account_sway_locale).to eq("cambridge-massachusetts-united_states")
        end
      end

      it "falls back to its own default when the locale name is unset" do
        with_env(SettingsSpecHelpers::VALID_DEV_ACCOUNT_ENV.merge("DEV_ACCOUNT_SWAY_LOCALE" => nil)) do
          expect(Sway::Settings::DevLogin.new.dev_account_sway_locale).to eq("baltimore-maryland-united_states")
        end
      end

      it "falls back to its default when one of the two is set to an empty string -- blank counts as absent here too" do
        with_env(SettingsSpecHelpers::VALID_DEV_ACCOUNT_ENV.merge("DEV_ACCOUNT_FULL_NAME" => "")) do
          expect(Sway::Settings::DevLogin.new.dev_account_full_name).to eq("Sway+Admin")
        end
      end

      it "boots with neither of the two set -- the CR-01 regression: a fresh clone with no .env.test/.env.development" do
        with_env(SettingsSpecHelpers::VALID_DEV_ACCOUNT_ENV.transform_values { nil }) do
          instance = Sway::Settings::DevLogin.new

          expect(instance.dev_account_full_name).to eq("Sway+Admin")
          expect(instance.dev_account_sway_locale).to eq("baltimore-maryland-united_states")
        end
      end

      it "boots through Sway::Settings.build! with neither of the two set -- CR-01, the actual boot path" do
        with_env(SettingsSpecHelpers::VALID_DEV_ACCOUNT_ENV.transform_values { nil }) do
          expect { Sway::Settings.build! }.not_to raise_error
        end
      end

      # @lat: [[identity-and-access#The stand-in account borrows a jurisdiction's sample address]]
      it "reads the locale name back as text" do
        with_env(SettingsSpecHelpers::VALID_DEV_ACCOUNT_ENV) do
          expect(Sway::Settings::DevLogin.new.dev_account_sway_locale).to be_a(String)
        end
      end
    end

    describe "the skip switch" do
      it "reads false when unset" do
        with_env(SettingsSpecHelpers::VALID_DEV_ACCOUNT_ENV.merge("SKIP_PHONE_VERIFICATION" => nil)) do
          instance = Sway::Settings::DevLogin.new

          expect(instance.skip_phone_verification).to eq(false)
        end
      end

      # @lat: [[settings-type-caster-design#Boolean: blank and unrecognized are not the same failure]]
      it "leaves the check ON (reads false) for every value that is not a recognized truthy word" do
        [nil, "", "   ", "banana", "0", "false"].each do |raw|
          with_env(SettingsSpecHelpers::VALID_DEV_ACCOUNT_ENV.merge("SKIP_PHONE_VERIFICATION" => raw)) do
            instance = Sway::Settings::DevLogin.new

            expect(instance.skip_phone_verification).to eq(false),
              "SKIP_PHONE_VERIFICATION=#{raw.inspect} left the switch on (should stay off)"
          end
        end
      end

      # Both tracked example files' actual values still mean the same thing
      # under the narrower caster.
      it "reads true for the values both example env files actually carry" do
        ["1", "true"].each do |raw|
          with_env(SettingsSpecHelpers::VALID_DEV_ACCOUNT_ENV.merge("SKIP_PHONE_VERIFICATION" => raw)) do
            instance = Sway::Settings::DevLogin.new

            expect(instance.skip_phone_verification).to eq(true),
              "SKIP_PHONE_VERIFICATION=#{raw.inspect} did not turn the switch on"
          end
        end
      end
    end
  end

  # @lat: [[mobile-settings-group-design#Design notes for the Mobile settings group]]
  describe "Sway::Settings::Mobile" do
    describe "the store id" do
      it "reads the placeholder when unset" do
        with_env("APPLE_APP_STORE_ID" => nil) do
          instance = Sway::Settings::Mobile.new

          expect(instance.apple_app_store_id).to eq("<APPLE_APP_ID>")
        end
      end

      it "reads a ten-digit id back as text, not a number" do
        with_env("APPLE_APP_STORE_ID" => "1234567890") do
          instance = Sway::Settings::Mobile.new

          expect(instance.apple_app_store_id).to eq("1234567890")
          expect(instance.apple_app_store_id).to be_a(String)
        end
      end
    end

    describe "the Apple team and bundle ids" do
      it "read nil when unset, so nothing falls back to one deployment's ids" do
        with_env("APPLE_TEAM_ID" => nil, "APPLE_BUNDLE_ID" => nil) do
          instance = Sway::Settings::Mobile.new

          expect(instance.apple_team_id).to be_nil
          expect(instance.apple_bundle_id).to be_nil
        end
      end

      it "strip a trailing newline from a value pasted out of the vault" do
        with_env("APPLE_TEAM_ID" => "ABCDE12345\n", "APPLE_BUNDLE_ID" => " app.example.test ") do
          instance = Sway::Settings::Mobile.new

          expect(instance.apple_team_id).to eq("ABCDE12345")
          expect(instance.apple_bundle_id).to eq("app.example.test")
        end
      end
    end

    describe "the app association hosts" do
      it "read an empty list when unset, so no host serves the association files" do
        with_env("APP_ASSOCIATION_HOSTS" => nil) do
          expect(Sway::Settings::Mobile.new.app_association_hosts).to eq([])
        end
      end

      it "split a comma-separated value, strip each entry and drop empty ones" do
        with_env("APP_ASSOCIATION_HOSTS" => " a.example.test, b.example.test ,, \n") do
          instance = Sway::Settings::Mobile.new

          expect(instance.app_association_hosts).to eq(%w[a.example.test b.example.test])
          expect(instance.app_association_hosts).to be_frozen
        end
      end
    end

    describe "the two version numbers" do
      it "default to 1.0.0 when unset" do
        with_env("MOBILE_MIN_VERSION" => nil, "MOBILE_LATEST_VERSION" => nil) do
          instance = Sway::Settings::Mobile.new

          expect(instance.mobile_min_version).to eq("1.0.0")
          expect(instance.mobile_latest_version).to eq("1.0.0")
        end
      end

      # The exact hazard the plan names: a one-decimal-point value becomes a
      # Float and a bare digit becomes an Integer under any automatic
      # reading, and the mobile client compares both versions as text.
      it "read a one-decimal and a bare-digit value back as text, not a number" do
        with_env("MOBILE_MIN_VERSION" => "1.5", "MOBILE_LATEST_VERSION" => "2") do
          instance = Sway::Settings::Mobile.new

          expect(instance.mobile_min_version).to eq("1.5")
          expect(instance.mobile_min_version).to be_a(String)
          expect(instance.mobile_latest_version).to eq("2")
          expect(instance.mobile_latest_version).to be_a(String)
        end
      end
    end

    describe "the Android fingerprint list" do
      it "returns an empty list when unset, when set to an empty string, and when set to spaces only" do
        [nil, "", "   "].each do |raw|
          with_env("ANDROID_CERT_SHA256_FINGERPRINTS" => raw) do
            instance = Sway::Settings::Mobile.new

            expect(instance.android_cert_sha256_fingerprints).to eq([]),
              "ANDROID_CERT_SHA256_FINGERPRINTS=#{raw.inspect} did not read back an empty list"
          end
        end
      end

      it "splits a comma-separated value, strips the spaces around each entry, and drops empty entries" do
        with_env("ANDROID_CERT_SHA256_FINGERPRINTS" => "AA:BB:CC, DD:EE:FF ,  , GG:HH:II") do
          instance = Sway::Settings::Mobile.new

          expect(instance.android_cert_sha256_fingerprints).to eq(%w[AA:BB:CC DD:EE:FF GG:HH:II])
        end
      end

      # WR-06: reaches app/controllers/well_known_controller.rb's
      # assetlinks.json response -- frozen, after the compact repair, so no
      # caller can mutate the list every other caller shares.
      it "is frozen" do
        with_env("ANDROID_CERT_SHA256_FINGERPRINTS" => "AA:BB:CC") do
          expect(Sway::Settings::Mobile.new.android_cert_sha256_fingerprints).to be_frozen
        end
      end
    end
  end

  # @lat: [[ops-settings-group-design#Why the frontend's IS_PRODUCTION reads the build, not the hostname]]
  describe "Sway::Settings::Ops" do
    # @lat: [[admin-hub-index#Who sees the monitoring link]]
    describe "the monitoring admin email domains" do
      it "reads an empty list when unset, so no admin sees the monitoring link" do
        with_env("BESZEL_ADMIN_EMAIL_DOMAINS" => nil) do
          expect(Sway::Settings::Ops.new.beszel_admin_email_domains).to eq([])
        end
      end

      it "splits a comma-separated value and drops empty entries" do
        with_env("BESZEL_ADMIN_EMAIL_DOMAINS" => "ops.example.org, ,staff.example.org,") do
          expect(Sway::Settings::Ops.new.beszel_admin_email_domains)
            .to eq(["ops.example.org", "staff.example.org"])
        end
      end
    end

    # @lat: [[seeded-development-users#Outbound SMS is refused outside production]]
    describe "the nonproduction SMS switch" do
      it "reads false (nothing leaves the machine) for every value that is not a recognized truthy word" do
        [nil, "", "   ", "banana", "0", "false"].each do |raw|
          with_env("ALLOW_NONPRODUCTION_SMS" => raw) do
            instance = Sway::Settings::Ops.new

            expect(instance.allow_nonproduction_sms).to eq(false),
              "ALLOW_NONPRODUCTION_SMS=#{raw.inspect} did not leave outbound SMS refused"
          end
        end
      end

      it "reads true for a recognized truthy word" do
        with_env("ALLOW_NONPRODUCTION_SMS" => "1") do
          instance = Sway::Settings::Ops.new

          expect(instance.allow_nonproduction_sms).to eq(true)
        end
      end
    end

    describe "the deploy stamp" do
      it "returns nil when unset, never a time" do
        with_env("SWAY_DEPLOYED_AT" => nil) do
          instance = Sway::Settings::Ops.new

          expect(instance.sway_deployed_at).to be_nil
        end
      end

      # The exact hazard config/deploy.yml's own comment names: an unquoted
      # value there is coerced into a Time that Time.iso8601 cannot re-parse.
      # The declaration must not repeat that mistake.
      it "reads a timestamp back as text, not a Time" do
        with_env("SWAY_DEPLOYED_AT" => "2026-07-30T09:00:00Z") do
          instance = Sway::Settings::Ops.new

          expect(instance.sway_deployed_at).to eq("2026-07-30T09:00:00Z")
          expect(instance.sway_deployed_at).to be_a(String)
        end
      end
    end

    # Correction from the orchestrator: missing, blank, and unreadable must
    # ALL leave backups on (sway_skip_db_backup == false). A misread that
    # silently answers true is the worst outcome in this group.
    describe "the backup skip switch" do
      it "reads false (backups stay on) for every value that is not a recognized truthy word" do
        [nil, "", "   ", "banana", "0", "false"].each do |raw|
          with_env("SWAY_SKIP_DB_BACKUP" => raw) do
            instance = Sway::Settings::Ops.new

            expect(instance.sway_skip_db_backup).to eq(false),
              "SWAY_SKIP_DB_BACKUP=#{raw.inspect} did not leave backups on"
          end
        end
      end

      it "reads true for a recognized truthy word" do
        with_env("SWAY_SKIP_DB_BACKUP" => "1") do
          instance = Sway::Settings::Ops.new

          expect(instance.sway_skip_db_backup).to eq(true)
        end
      end
    end

    describe "the container switch" do
      it "reads false when unset and when set to an empty string" do
        [nil, ""].each do |raw|
          with_env("IS_DOCKER" => raw) do
            instance = Sway::Settings::Ops.new

            expect(instance.is_docker).to eq(false)
          end
        end
      end

      it "reads true for a recognized truthy word" do
        with_env("IS_DOCKER" => "true") do
          instance = Sway::Settings::Ops.new

          expect(instance.is_docker).to eq(true)
        end
      end
    end

    describe "the tunnel host" do
      it "returns nil when unset and when set to spaces only" do
        [nil, "   "].each do |raw|
          with_env("DEV_TUNNEL_HOST" => raw) do
            instance = Sway::Settings::Ops.new

            expect(instance.dev_tunnel_host).to be_nil
          end
        end
      end

      it "returns the host when set" do
        with_env("DEV_TUNNEL_HOST" => "sway-dev.example.com") do
          instance = Sway::Settings::Ops.new

          expect(instance.dev_tunnel_host).to eq("sway-dev.example.com")
        end
      end
    end

    describe "the Beszel dashboard URL" do
      it "returns nil when unset and when set to spaces only" do
        [nil, "   "].each do |raw|
          with_env("BESZEL_URL" => raw) do
            instance = Sway::Settings::Ops.new

            expect(instance.beszel_url).to be_nil
          end
        end
      end

      it "returns the URL when set" do
        with_env("BESZEL_URL" => "http://203.0.113.10:8090") do
          instance = Sway::Settings::Ops.new

          expect(instance.beszel_url).to eq("http://203.0.113.10:8090")
        end
      end
    end
  end

  # Two names sharing one prefix: which origins may complete a passkey
  # ceremony, and the domain a passkey is tied to (T-68-36 through T-68-38).
  # No spec varied either name before this plan -- both readers read raw
  # ENV, so this is the only group in the phase with nothing to migrate.
  describe "Sway::Settings::Webauthn" do
    describe "the related hosts" do
      it "read an empty list when unset, so no host serves the related-origin file" do
        with_env("WEBAUTHN_RELATED_HOSTS" => nil) do
          expect(Sway::Settings::Webauthn.new.related_hosts).to eq([])
        end
      end

      it "split a comma-separated value, strip each entry and drop empty ones" do
        with_env("WEBAUTHN_RELATED_HOSTS" => "a.example.test, ,b.example.test\n") do
          instance = Sway::Settings::Webauthn.new

          expect(instance.related_hosts).to eq(%w[a.example.test b.example.test])
          expect(instance.related_hosts).to be_frozen
        end
      end
    end

    describe "the allowed origins" do
      it "returns an empty list when unset, when set to an empty string, and when set to spaces only" do
        [nil, "", "   "].each do |raw|
          with_env("WEBAUTHN_ALLOWED_ORIGINS" => raw) do
            instance = Sway::Settings::Webauthn.new

            expect(instance.allowed_origins).to eq([]),
              "WEBAUTHN_ALLOWED_ORIGINS=#{raw.inspect} did not read back an empty list"
          end
        end
      end

      it "splits a comma-separated value, strips the spaces around each entry, and drops empty entries" do
        with_env("WEBAUTHN_ALLOWED_ORIGINS" => "https://a.example, https://b.example ,  , https://c.example") do
          instance = Sway::Settings::Webauthn.new

          expect(instance.allowed_origins).to eq(%w[https://a.example https://b.example https://c.example])
        end
      end

      # The exact hazard a `kamal env push` trailing newline creates: the
      # newline sits on the LAST entry, not between entries, so a per-line
      # scan of the raw value would miss it.
      it "removes a trailing newline from the last entry" do
        with_env("WEBAUTHN_ALLOWED_ORIGINS" => "https://a.example,https://b.example\n") do
          instance = Sway::Settings::Webauthn.new

          expect(instance.allowed_origins).to eq(%w[https://a.example https://b.example])
        end
      end

      # WR-06: this array reaches WebAuthn::RelyingParty.new and
      # /.well-known/assetlinks.json -- one caller mutating the object every
      # other caller shares would corrupt a security boundary for the
      # process's whole lifetime, not just that one request.
      it "is frozen, after the compact repair, so no caller can mutate the list every other caller shares" do
        with_env("WEBAUTHN_ALLOWED_ORIGINS" => "https://a.example,https://b.example") do
          expect(Sway::Settings::Webauthn.new.allowed_origins).to be_frozen
        end
      end
    end

    describe "the relying party domain" do
      it "returns nil when unset and when set to spaces only" do
        [nil, "   "].each do |raw|
          with_env("WEBAUTHN_RP_ID" => raw) do
            instance = Sway::Settings::Webauthn.new

            expect(instance.rp_id).to be_nil
          end
        end
      end

      it "removes surrounding whitespace from a value that is not blank" do
        with_env("WEBAUTHN_RP_ID" => "  app.sway.vote\n") do
          instance = Sway::Settings::Webauthn.new

          expect(instance.rp_id).to eq("app.sway.vote")
        end
      end
    end
  end
end
