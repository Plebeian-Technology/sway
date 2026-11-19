# frozen_string_literal: true

# @lat: [[env-credential-scanner-design#Why the credential scanner walks every tracked file]]
class EnvCredentialScanner
  # @lat: [[rbs-signatures#Why a typed spec double is a plain class rather than a Struct]]
  class Read
    attr_reader :path, :line, :name, :source, :stripped

    def initialize(path:, line:, name:, source:, stripped:)
      @path = path
      @line = line
      @name = name
      @source = source
      @stripped = stripped
    end

    def to_s
      "#{path}:#{line} #{name} -- #{source}"
    end
  end

  # Directories and file types the scan does not enter, each for a written-down
  # reason rather than by inheriting somebody else's --include filter.
  SKIPPED_PREFIXES = [
    # Documentation and agent notes quote code; they run nothing.
    ".agents/",
    "docs/",
    # A separate package with its own runtime; it ships no server credential.
    "mobile/",
    # Third-party code, not ours.
    "node_modules/",
    # Specs SET credential environment variables on purpose (see with_env in
    # env_secret_call_sites_spec.rb) and never run in production, so an
    # untrimmed read there cannot send a bad value anywhere real.
    "spec/"
  ].freeze

  SKIPPED_EXTENSIONS = %w[
    .md .json .lock .png .jpg .jpeg .svg .ico .woff .woff2 .ttf .pdf .sqlite3
  ].freeze

  # Files the scan reads but whose findings are allowed through, with the
  # evidence for each. An entry here is a claim that has to stay true.
  EXEMPT_PATHS = {
    ".kamal/hooks/pre-deploy.sample" =>
      "A .sample file. Kamal executes .kamal/hooks/<name> only — the .sample suffix " \
      "is what makes it a template rather than a hook — so this never runs.",
    ".kamal/hooks/pre-deploy" =>
      "Tests only whether OPEN_STATES_API_KEY is empty, to refuse a deploy without it. " \
      "The hook never sends the value anywhere, so an untrimmed value cannot degrade " \
      "silently here; the running app reads the key through EnvSecret.",
    "scripts/twilio/approve-verification.sh" =>
      "A manual operator curl run from a laptop against Twilio's Verify API, not a " \
      "deployed process. It genuinely CONSUMES the credentials (curl -u), so it is " \
      "not pass-through — but a newline fails the curl loudly, immediately, and in " \
      "front of the person who typed the command, which is the opposite of the " \
      "silent-degradation failure mode this guard exists for."
  }.freeze

  # What a read looks like, in any language that can hold one. The `$VAR` and
  # `${VAR}` forms catch shell scripts, Docker Compose files and Dockerfiles —
  # which the Ruby-only sweep could not see either.
  READ_PATTERNS = [
    /ENV\s*\[\s*["']([A-Z0-9_]+)["']/,
    /ENV\s*\.\s*fetch\s*\(\s*["']([A-Z0-9_]+)["']/,
    /EnvSecret\s*\.\s*(?:read|fetch!|read_base64)\s*\(\s*["']([A-Z0-9_]+)["']/,
    /\$\{?([A-Z0-9_]+)\}?/
  ].freeze

  # @lat: [[env-credential-scanner-design#Why some credentials are listed by hand]]
  APNS_FCM_AND_TWILIO_CREDENTIALS = %w[
    APNS_ENV
    APNS_SANDBOX_AUTH_KEY_P8
    APNS_SANDBOX_KEY_ID
    FCM_PROJECT_ID
    SWAY_DATABASE_PASSWORD
  ].freeze

  # @lat: [[env-credential-scanner-design#Why the WebAuthn names stay listed though the scan cannot see them]]
  WEBAUTHN_CREDENTIALS = %w[
    WEBAUTHN_ALLOWED_ORIGINS
    WEBAUTHN_RP_ID
  ].freeze

  EXTRA_CREDENTIALS = (APNS_FCM_AND_TWILIO_CREDENTIALS + WEBAUTHN_CREDENTIALS).freeze

  # Names that come from .kamal/secrets-common but are not credentials the Rails
  # process reads, or are used by tools outside it. Each needs a reason.
  NON_APP_CREDENTIALS = {
    "SECRETS" => "the Kamal secret-source declaration, not a variable",
    "KAMAL_REGISTRY_PASSWORD" => "consumed by Kamal on the deploy host, never by the app",
    "TUNNEL_TOKEN" => "consumed by the cloudflared container, never by the app",
    "BESZEL_AGENT_KEY" => "consumed by the beszel_agent container, never by the app",
    "SENTRY_AUTH_TOKEN" => "build-time source-map upload only (config/deploy.yml builder secret)",
    "SENTRY_ORG" => "not a credential",
    "SENTRY_PROJECT" => "not a credential",
    "GITHUB_REPO" => "not a credential — an owner/repo slug",
    "SWAY_SECRETS_FETCH" => "not a credential — the fetch command scripts/lib/secrets.sh prints for the chosen secret store",
    "GOOGLE_CLOUD_PROJECT" => "not a credential — a project id",
    "NEW_RELIC_ACCOUNT_ID" => "not a credential — an account id",
    "ADMIN_PHONES" => "a phone list, whitespace-immune via String#normalize_phone -- verified, " \
      "not merely asserted, by spec/models/user_spec.rb on Ruby 4.0.10 (68-03)"
  }.freeze

  # @lat: [[env-credential-scanner-design#Why an undelivered credential is a claim rather than a silencer]]
  UNDELIVERED_CREDENTIALS = {
    "SWAY_DATABASE_PASSWORD" => "nothing reads it — SQLite takes no password",
    "APNS_SANDBOX_AUTH_KEY_P8" => "production runs APNS_ENV=production and reads only the production pair; " \
      "the sandbox key belongs in a local .env for development builds",
    "APNS_SANDBOX_KEY_ID" => "production runs APNS_ENV=production and reads only the production pair; " \
      "the sandbox key belongs in a local .env for development builds"
  }.freeze

  # Anything starting with VITE_ is compiled into the browser bundle by
  # definition, so it is public and cannot be a secret in transit.
  PUBLIC_PREFIXES = %w[VITE_].freeze

  # @lat: [[env-credential-scanner-design#Why the trim check looks a few lines past the read]]
  CONTINUATION_WINDOW_LINES = 3

  def initialize(root: Rails.root)
    @root = root
  end

  # @return [Array<String>] credential variable names, taken from the file that
  #   decides which secrets exist, so a newly added secret gets checked without
  #   anyone remembering to list it here.
  def credential_names
    @credential_names ||= (provisioned + EXTRA_CREDENTIALS - NON_APP_CREDENTIALS.keys)
      .reject { |name| PUBLIC_PREFIXES.any? { |prefix| name.start_with?(prefix) } }
      .uniq
      .sort
      .freeze
  end

  # @return [Array<Read>] every credential read the scan can see.
  def reads
    @reads ||= scannable_paths.flat_map { |path| reads_in(path) }
  end

  # @return [Array<Read>] the ones that neither go through EnvSecret nor trim.
  def unstripped
    reads.reject(&:stripped)
  end

  private

  attr_reader :root

  def provisioned
    @root.join(".kamal/secrets-common").readlines.filter_map { |line| line[/\A([A-Z0-9_]+)=/, 1] }
  end

  def scannable_paths
    `git ls-files -z`.split("\0").reject do |path|
      SKIPPED_PREFIXES.any? { |prefix| path.start_with?(prefix) } ||
        SKIPPED_EXTENSIONS.include?(File.extname(path).downcase) ||
        EXEMPT_PATHS.key?(path) ||
        !root.join(path).file?
    end
  end

  # A line counts as reading `name` if it mentions the name inside one of the
  # read forms. Comment lines are skipped: a commented-out read sends nothing
  # anywhere, and the alternative would be one exemption entry for every time
  # the name is mentioned in prose.
  def reads_in(path)
    lines = root.join(path).readlines
    lines.each_with_index.filter_map do |line, index|
      next unless line.valid_encoding?
      next if line.strip.start_with?("#")

      name = credential_name_in(line)
      next if name.nil?

      Read.new(
        path: path, line: index + 1, name: name,
        source: line.strip, stripped: stripped?(lines, index)
      )
    end
  rescue ArgumentError
    # Binary content that slipped the extension filter.
    []
  end

  def credential_name_in(line)
    READ_PATTERNS
      .flat_map { |pattern| line.scan(pattern) }
      .flatten
      .uniq
      .find do |name|
        credential_names.include?(name) &&
          !pass_through?(line, name) &&
          !assignment?(line, name)
      end
  end

  # @lat: [[env-credential-scanner-design#Why plumbing a variable to a child process is not a read]]
  def pass_through?(line, name)
    escaped = Regexp.escape(name)
    line.match?(/(?:\A|[\s;"'])(?:export\s+)?#{escaped}\s*[:=]\s*["']?\$\{?#{escaped}\b/)
  end

  # `ENV["NAME"] = value` — a WRITE. It sends nothing anywhere; if anything it
  # is how a value gets tidied up (config/boot.rb does exactly this for
  # NEW_RELIC_LICENSE_KEY, which newrelic_rpm reads out of the environment
  # itself). Matched on a single `=` so `ENV["NAME"] ==` stays a read.
  def assignment?(line, name)
    line.match?(/ENV\s*\[\s*["']#{Regexp.escape(name)}["']\s*\]\s*=[^=]/)
  end

  # Looks for `.strip`, `&:strip`, or a call through EnvSecret, across the few
  # lines one call can span (see CONTINUATION_WINDOW_LINES).
  def stripped?(lines, index)
    window = lines[index, CONTINUATION_WINDOW_LINES + 1].to_a.join(" ")
    window.include?("EnvSecret.") || window.match?(/(?:\.|&:)strip\b/)
  end
end
