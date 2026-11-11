# frozen_string_literal: true

require "rails_helper"

# Server-side request forgery: MatterAttachmentHyperlink is a FULL URL from
# Legistar, and Faraday treats it as replacing the connection's url_prefix.
RSpec.describe Legistar::AttachmentUrl do
  describe ".allowed?" do
    # A23-03: the old example title claimed to match every cassette row, but
    # its assertion never connected to the recording — now made where
    # checkable.
    it "accepts other Legistar client subdomains and the API host" do
      expect(described_class.allowed?("https://annapolis.legistar1.com/x.pdf")).to be(true)
      expect(described_class.allowed?("https://webapi.legistar.com/v1/x.pdf")).to be(true)
      expect(described_class.allowed?("https://legistar.com/x.pdf")).to be(true)
    end

    it "is case-insensitive on the host, as DNS is" do
      expect(described_class.allowed?("https://Baltimore.Legistar1.COM/x.pdf")).to be(true)
    end

    it "rejects plaintext http even on an allowed host" do
      expect(described_class.allowed?("http://baltimore.legistar1.com/x.pdf")).to be(false)
    end

    it "rejects the cloud metadata endpoint, loopback, and link-local addresses" do
      expect(described_class.allowed?("http://169.254.169.254/latest/meta-data/")).to be(false)
      expect(described_class.allowed?("https://169.254.169.254/latest/meta-data/")).to be(false)
      expect(described_class.allowed?("http://127.0.0.1:9292/")).to be(false)
      expect(described_class.allowed?("https://localhost/")).to be(false)
    end

    it "rejects a sibling container on the docker network" do
      expect(described_class.allowed?("http://rails:3000/admin")).to be(false)
    end

    it "rejects non-http schemes outright" do
      expect(described_class.allowed?("file:///etc/passwd")).to be(false)
      expect(described_class.allowed?("gopher://baltimore.legistar1.com/")).to be(false)
    end

    it "rejects a host that merely ENDS WITH the allowed apex" do
      expect(described_class.allowed?("https://evil-legistar1.com/x.pdf")).to be(false)
      expect(described_class.allowed?("https://legistar1.com.attacker.test/x.pdf")).to be(false)
    end

    # The allow-or-deny decision must run on the FULL host. Cutting to 100
    # chars before matching could CREATE a match the real host lacks, since
    # ALLOWED_HOST anchors to the string end.
    it "rejects a host whose first 100 characters end in an allowed apex" do
      label = "a" * 86
      url = "https://#{label}.legistar1.com.attacker.test/x.pdf"

      host = URI.parse(url).host
      raise "test URL has no host: #{url}" if host.nil?
      checked_host = host #: String

      expect(checked_host[0, 100]).to end_with(".legistar1.com")
      expect(described_class.allowed?(url)).to be(false)
    end

    it "rejects the same truncation bypass on the trailing-dot form" do
      label = "a" * 86

      expect(described_class.allowed?("https://#{label}.legistar1.com.attacker.test./x.pdf")).to be(false)
    end

    it "rejects an allowed host reached on a non-default port" do
      expect(described_class.allowed?("https://baltimore.legistar1.com:9292/x.pdf")).to be(false)
    end

    it "rejects userinfo smuggling" do
      expect(described_class.allowed?("https://baltimore.legistar1.com@attacker.test/x.pdf")).to be(false)
    end

    it "rejects blank, nil and unparseable input without raising" do
      expect(described_class.allowed?(nil)).to be(false)
      expect(described_class.allowed?("")).to be(false)
      expect(described_class.allowed?("   ")).to be(false)
      expect(described_class.allowed?("https://exa mple.com/ %")).to be(false)
      expect(described_class.allowed?(12_345)).to be(false)
    end

    # String#strip raises CompatibilityError on invalid UTF-8 — neither
    # Rejected nor Faraday::Error, so it escapes rescue and kills the run.
    # be(false), since dropping bad bytes could hide a bad host.
    it "rejects a url carrying invalid UTF-8 without raising" do
      expect(described_class.allowed?("https://baltimore.legistar1.com/\xC3(.pdf")).to be(false)
    end

    it "rejects invalid UTF-8 that would otherwise close up into an allowed host" do
      expect(described_class.allowed?("https://baltimore.legistar1\xC3.com.attacker.test/x.pdf")).to be(false)
    end
  end

  describe ".rejection_reason" do
    it "is nil for an allowed url" do
      expect(described_class.rejection_reason("https://baltimore.legistar1.com/x.pdf")).to be_nil
    end

    it "names the scheme and the host without echoing the whole url back into the admin surface" do
      reason = described_class.rejection_reason("http://169.254.169.254/latest/meta-data/iam/")
      expect(reason).to include("169.254.169.254")
      expect(reason).not_to include("meta-data")
    end

    # MAX_REASON_LENGTH was referenced nowhere in app/, lib/, sig/ or spec/.
    # Reasons were trimmed ad hoc at three different numbers, none the named
    # constant.
    it "bounds every reason it returns at MAX_REASON_LENGTH" do
      long_host = "#{"a" * 400}.attacker.test"
      reasons = [
        described_class.rejection_reason(nil),
        described_class.rejection_reason("   "),
        described_class.rejection_reason("https://exa mple.com/ %"),
        described_class.rejection_reason("http://#{long_host}/x"),
        described_class.rejection_reason("https://user:pw@baltimore.legistar1.com/x"),
        described_class.rejection_reason("https://#{long_host}/x"),
        described_class.rejection_reason("https://baltimore.legistar1.com:9292/x")
      ]

      expect(reasons).to all(be_present)
      reasons.each { |reason| expect(reason.length).to be <= described_class::MAX_REASON_LENGTH }
    end

    # A23-04: uri.port has no cap of its own, so it's the only input proving
    # MAX_REASON_LENGTH applies. eq, not <=, so dropping bounded OR moving
    # the constant alone fails this.
    it "bounds the one reason no per-component cap covers" do
      reason = described_class.rejection_reason("https://baltimore.legistar1.com:#{"9" * 400}/x")

      expect(reason).to be_present
      expect(reason.length).to eq(described_class::MAX_REASON_LENGTH)
    end

    # A trailing dot is a legal, fully-qualified host name. It used to be
    # rejected, safely, but if Legistar sent one, every attachment on every
    # bill would fail for no obvious reason.
    it "accepts a fully-qualified trailing-dot form of an allowed host" do
      expect(described_class.allowed?("https://baltimore.legistar1.com./x.pdf")).to be(true)
    end

    it "does not let a trailing dot smuggle a disallowed host through" do
      expect(described_class.allowed?("https://evil-legistar1.com./x.pdf")).to be(false)
      expect(described_class.allowed?("https://legistar1.com.attacker.test./x.pdf")).to be(false)
    end
  end

  # A22-03/A23-01/A24-02: earlier fixes to restated figures were wrong or
  # unfalsifiable. These ASSERT every figure other comments lean on; grep
  # the SHAPE to find restatements.
  describe "the reference cassette the allowlist was read off" do
    # Named off the cassette, not cassette/hyperlinks: sig-test/object_spec_methods.rbs
    # declares ONE signature per method name for the whole suite, so a
    # generic name would claim it suite-wide.
    let(:endpoint_probe_cassette) do
      Rails.root.join("spec", "cassettes", "legistar_testimony_endpoint_probe.yml").read
    end
    let(:probe_attachment_hyperlinks) do
      endpoint_probe_cassette.scan(/"MatterAttachmentHyperlink"\s*:\s*"([^"]*)"/).flatten
    end
    let(:probe_attachment_file_names) do
      endpoint_probe_cassette.scan(/"MatterAttachmentFileName"\s*:\s*"([^"]*)"/).flatten
    end
    let(:probe_attachment_display_names) do
      endpoint_probe_cassette.scan(/"MatterAttachmentName"\s*:\s*"([^"]*)"/).flatten
    end

    it "carries 28 attachment rows" do
      expect(probe_attachment_hyperlinks.length).to eq(28)
      expect(probe_attachment_file_names.length).to eq(28)
      expect(probe_attachment_display_names.length).to eq(28)
    end

    # Two names repeat across the 28 rows, which is why display-name figures
    # are counted distinct and row figures are not. Both are leaned on by
    # comments elsewhere; neither was measured until now.
    it "carries 25 distinct display names across those rows" do
      expect(probe_attachment_display_names.uniq.length).to eq(25)
    end

    # The provenance argument in ClassificationPromptBuilder rests on this: a
    # Name ending in a document extension is pre-filled, not clerk-typed. Any
    # dot suffix gives 21; extensions give 19.
    it "has a document extension on 19 of those 25 names" do
      with_document_extension = probe_attachment_display_names.uniq.count do |name|
        name.match?(/\.(pdf|docx?|xlsx?|jpe?g|png|txt)\z/i)
      end

      expect(with_document_extension).to eq(19)
    end

    # The other half of the same argument: the STORED name is a Legistar GUID,
    # so it is not attacker-controlled, and it never equals the display Name.
    it "never stores the display name as the file name" do
      pairs = probe_attachment_display_names.zip(probe_attachment_file_names)

      expect(pairs.any? { |display, stored| display == stored }).to be(false)
    end

    it "puts every one of them on https://baltimore.legistar1.com" do
      schemes_and_hosts = probe_attachment_hyperlinks.map do |url|
        parsed = URI.parse(url)
        [parsed.scheme, parsed.host]
      end

      expect(schemes_and_hosts.uniq).to eq([["https", "baltimore.legistar1.com"]])
    end

    # The .jpg the candidate-cap comment used to cite is not here. The gate it
    # justifies is still right — Legistar accepts any file type — but the
    # cassette is not the evidence for it.
    it "carries no non-PDF upstream file name" do
      expect(probe_attachment_file_names.map { |name| File.extname(name).downcase }.uniq).to eq([".pdf"])
    end

    # A23-03: the allowlist was derived from these rows, but nothing ran one
    # through it until now — pinned AGAINST the recording, so a re-recording
    # moving hosts fails here.
    it "accepts every attachment url in the reference recording" do
      expect(probe_attachment_hyperlinks).to be_present

      probe_attachment_hyperlinks.each do |url|
        expect(described_class.rejection_reason(url)).to be_nil, "rejected a recorded url: #{url}"
      end
    end
  end
end
