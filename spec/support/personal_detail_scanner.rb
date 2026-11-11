# frozen_string_literal: true

# @lat: [[lat.md/explanation/personal-detail-scanner-design#Why the personal-detail scanner inverts the credential scanner's skip list]]
class PersonalDetailScanner
  # One planted detail, at the place it was found.
  class Finding
    attr_reader :path, :line, :kind, :source, :exempt

    def initialize(path:, line:, kind:, source:, exempt:)
      @path = path
      @line = line
      @kind = kind
      @source = source
      @exempt = exempt
    end

    def to_s
      "#{path}:#{line} #{kind} -- #{source}"
    end
  end

  # Directories the scan does not enter, each for a written-down reason. This
  # list stays short on purpose: a documentation page, a seed fixture, or a
  # committed bill JSON dump can all carry a constituent's real detail just as
  # easily as an eval answer can, so nothing here is skipped for convenience.
  SKIPPED_PREFIXES = [
    # Third-party code, not ours.
    "node_modules/",
    ".pnpm-store/",
    # LEGISLATION_ROOT's own artifact tree. Nothing under it is ever
    # committed (.gitignore:119-137), but the prefix stays as a second,
    # defensive layer against a future accidental `git add -f`.
    "legislation/"
  ].freeze

  # The allow-list this scanner inverts EnvCredentialScanner's skip list into.
  # That scanner's SKIPPED_EXTENSIONS excludes .json and .md outright, because
  # a credential cannot live in either without also being unusable as a
  # credential. A constituent's detail is exactly as readable in an eval
  # verdict's JSON body or a documentation page's prose, so those are this
  # scanner's whole reason to exist and must not be skipped.
  SCANNED_EXTENSIONS = %w[.json .md].freeze

  # Reasons reused across EXEMPT_PATHS entries below. Each is a claim that has
  # to stay true; a path earns its way onto this table only by matching one.
  PLACEHOLDER_EMAIL =
    "An RFC 2606 reserved example domain (example.com/.org/.net) or an " \
    "obviously fake single-letter mailbox (x@y.com), used as literal " \
    "placeholder text in a code sample or test-fixture description. Never a " \
    "real address."
  PLACEHOLDER_PHONE =
    "A placeholder phone number -- the 410-555-01xx/555-xxxx block this " \
    "repo's own docs and UI copy use throughout, matching the " \
    "NANP-reserved fictional exchange. Never a real subscriber number."
  SWAY_OWN_CONTACT =
    "Sway's own published organizational contact: an @sway.vote address " \
    "(support/outreach/admin/legis/github/donations/no-reply/security) -- " \
    "a business address, not a constituent's."
  PUBLIC_GOV_CONTACT =
    "A public official's or government office's own published contact " \
    "info, sourced from the jurisdiction's own legislator directory (or a " \
    "bill title naming a real, publicly-recorded address) -- exactly the " \
    "public data Sway exists to surface, not a constituent's personal detail."

  # path => the evidence for accepting that path's findings. An entry earns
  # its way in only by matching one of the reasons above; every path here was
  # checked by hand against the source line it was flagged for.
  EXEMPT_PATHS = {
    "README.md" => SWAY_OWN_CONTACT,
    "SECURITY.md" => SWAY_OWN_CONTACT,
    "db/seeds/data/united_states/maryland/annapolis/legislators.json" =>
      "Annapolis City Council members' own published government emails and office phone numbers -- #{PUBLIC_GOV_CONTACT}",
    "db/seeds/data/united_states/maryland/baltimore/legislators.json" =>
      "Baltimore City Council members' own published government emails, office phone " \
      "numbers and City Hall's public street address (100 Holliday Street) -- #{PUBLIC_GOV_CONTACT}",
    "db/seeds/data/united_states/maryland/maryland/legislators.json" =>
      "Maryland General Assembly members' own published government emails -- #{PUBLIC_GOV_CONTACT}",
    "docs/explanation/bill-entry-title-category-qualifier-split.md" =>
      "A real bill's title naming a real, publicly-recorded rezoning address (2400 Boston Street) -- #{PUBLIC_GOV_CONTACT}",
    "docs/explanation/phone-verification-rate-limits.md" => PLACEHOLDER_PHONE,
    "docs/kamal-secrets.md" => PLACEHOLDER_EMAIL,
    "docs/reference/admin-gate-shared-examples.md" => PLACEHOLDER_EMAIL,
    "lat.md/explanation/address-normalized-key.md" => PUBLIC_GOV_CONTACT,
    "lat.md/explanation/outbound-email.md" => SWAY_OWN_CONTACT,
    "lat.md/explanation/personal-detail-encryption.md" =>
      "The development seed graph's generated addresses on Sway's own " \
      "dev-baltimore.sway.vote subdomain. The local part is the row index, no " \
      "mailbox exists, and no person is named.",
    "lat.md/explanation/phone-cache-hashing.md" => PLACEHOLDER_PHONE
  }.freeze

  STREET_TYPE_SUFFIXES = %w[
    Street St Avenue Ave Road Rd Boulevard Blvd Drive Dr Lane Ln Way
    Court Ct Place Pl Circle Cir Terrace Ter Parkway Pkwy Highway Hwy
  ].freeze

  # @lat: [[personal-detail-scanner-design#Why the patterns over-report]]
  DETAIL_PATTERNS = {
    email: /\b[A-Za-z0-9][A-Za-z0-9._%+-]*@[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}\b/,
    street_address: /\b\d{1,6}\s+(?:[NSEW]\.?\s+|North\s+|South\s+|East\s+|West\s+)?
      (?:[A-Z][A-Za-z']*\.?\s+){1,3}(?:#{STREET_TYPE_SUFFIXES.join("|")})\.?\b/x,
    phone: /(?<!\d)(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]\d{3}[-.\s]\d{4}(?!\d)/
  }.freeze

  def initialize(root: Rails.root)
    @root = root
  end

  # @return [Array<Finding>] every planted detail the scan can see, including
  #   the ones EXEMPT_PATHS allows through.
  def findings
    @findings ||= scannable_paths.flat_map { |path| findings_in(path) }
  end

  # @return [Array<Finding>] the findings nothing has vouched for.
  def unexempt
    @unexempt ||= findings.reject(&:exempt)
  end

  private

  attr_reader :root

  # `git -C <root> ls-files -z`, run through an argv array rather than a
  # shell string so a root path containing a space is never re-interpreted --
  # the analog's bare backtick call relies on always running from Rails.root,
  # which does not hold once a spec roots this scanner at a temporary tree.
  def raw_paths
    IO.popen(["git", "-C", root.to_s, "ls-files", "-z"]) { |io| io.read }.split("\0")
  end

  def scannable_paths
    raw_paths.reject do |path|
      SKIPPED_PREFIXES.any? { |prefix| path.start_with?(prefix) } ||
        !SCANNED_EXTENSIONS.include?(File.extname(path).downcase) ||
        !root.join(path).file?
    end
  end

  def findings_in(path)
    exempt = EXEMPT_PATHS.key?(path)
    lines = root.join(path).readlines
    lines.each_with_index.flat_map do |line, index|
      next [] unless line.valid_encoding?

      DETAIL_PATTERNS.filter_map do |kind, pattern|
        next unless line.match?(pattern)

        Finding.new(path: path, line: index + 1, kind: kind, source: line.strip, exempt: exempt)
      end
    end
  rescue ArgumentError
    # Binary content that slipped the extension filter.
    []
  end
end
