# frozen_string_literal: true

require "rails_helper"

# @lat: [[outbound-fetch-safety#Every redirect hop is checked before it is followed]]
RSpec.describe Legistar::AttachmentFetch do
  let(:connection) { Sway::FaradayStack.legistar_attachment }
  let(:attachment_fetcher) { described_class.new(connection: connection) }

  let(:attachment_start_url) { "https://baltimore.legistar1.com/baltimore/attachments/1.pdf" }

  it "returns the response for a terminal 2xx without following anything" do
    stub_request(:get, attachment_start_url).to_return(status: 200, body: "%PDF-1.4 ok")

    response = attachment_fetcher.call(attachment_start_url)

    expect(response.status).to eq(200)
    expect(response.body).to eq("%PDF-1.4 ok")
  end

  it "follows a redirect to another allowed Legistar host" do
    hop = "https://baltimore.legistar1.com/cdn/1.pdf"
    stub_request(:get, attachment_start_url).to_return(status: 302, headers: {"Location" => hop})
    stub_request(:get, hop).to_return(status: 200, body: "%PDF-1.4 moved")

    expect(attachment_fetcher.call(attachment_start_url).body).to eq("%PDF-1.4 moved")
  end

  it "resolves a relative Location against the current hop" do
    stub_request(:get, attachment_start_url).to_return(status: 301, headers: {"Location" => "/baltimore/other.pdf"})
    stub_request(:get, "https://baltimore.legistar1.com/baltimore/other.pdf")
      .to_return(status: 200, body: "%PDF-1.4 relative")

    expect(attachment_fetcher.call(attachment_start_url).body).to eq("%PDF-1.4 relative")
  end

  it "revalidates every hop — a redirect off the allowlist is never requested" do
    stub_request(:get, attachment_start_url).to_return(status: 302, headers: {"Location" => "http://169.254.169.254/latest/"})
    probe = stub_request(:get, "http://169.254.169.254/latest/")

    expect { attachment_fetcher.call(attachment_start_url) }.to raise_error(described_class::Rejected, /169\.254\.169\.254/)
    expect(probe).not_to have_been_requested
  end

  it "rejects the initial url when it is off the allowlist, before any request" do
    probe = stub_request(:get, "http://127.0.0.1:9292/")

    expect { attachment_fetcher.call("http://127.0.0.1:9292/") }.to raise_error(described_class::Rejected)
    expect(probe).not_to have_been_requested
  end

  it "bounds the hop count rather than following a redirect loop forever" do
    stub_request(:get, %r{baltimore\.legistar1\.com/loop})
      .to_return(status: 302, headers: {"Location" => "https://baltimore.legistar1.com/loop"})

    expect { attachment_fetcher.call("https://baltimore.legistar1.com/loop") }
      .to raise_error(described_class::Rejected, /too many redirects/)
  end

  it "rejects a 3xx that carries no Location header" do
    stub_request(:get, attachment_start_url).to_return(status: 302)

    expect { attachment_fetcher.call(attachment_start_url) }.to raise_error(described_class::Rejected, /no Location/)
  end

  it "lets a Faraday transport error through so the caller keeps owning it and makes exactly 2 attempts" do
    req = stub_request(:get, attachment_start_url).to_raise(Faraday::ConnectionFailed.new("boom"))

    expect { attachment_fetcher.call(attachment_start_url) }.to raise_error(Faraday::Error)
    expect(req).to have_been_made.times(2)
  end

  # The checker parsed url.strip while the request used the unstripped
  # string, so a padded hyperlink passed the allowlist then raised
  # URI::InvalidURIError, which killed the whole run.
  describe "url normalization" do
    it "validates and requests the SAME normalized url when the hyperlink is whitespace-padded" do
      padded = "  https://baltimore.legistar1.com/baltimore/attachments/1.pdf\n"
      request = stub_request(:get, attachment_start_url).to_return(status: 200, body: "%PDF-1.4 ok")

      expect(attachment_fetcher.call(padded).body).to eq("%PDF-1.4 ok")
      expect(request).to have_been_requested
    end

    it "still rejects a padded url that is off the allowlist, before any request" do
      probe = stub_request(:get, "http://169.254.169.254/latest/")

      expect { attachment_fetcher.call("\n http://169.254.169.254/latest/ ") }
        .to raise_error(described_class::Rejected)
      expect(probe).not_to have_been_requested
    end

    # The same escalation from a different byte: a UTF-8-tagged hyperlink
    # with an invalid byte raised Encoding::CompatibilityError from a bare
    # .strip. Both sites now share AttachmentUrl.normalize.
    it "refuses a hyperlink carrying invalid UTF-8 as a per-attachment Rejected" do
      expect { attachment_fetcher.call("https://baltimore.legistar1.com/\xC3(.pdf") }
        .to raise_error(described_class::Rejected)
    end

    it "refuses a Location header carrying invalid UTF-8 as a per-attachment Rejected" do
      stub_request(:get, attachment_start_url)
        .to_return(status: 302, headers: {"Location" => "https://baltimore.legistar1.com/\xC3(.pdf"})

      expect { attachment_fetcher.call(attachment_start_url) }
        .to raise_error(described_class::Rejected)
    end

    # The method's own comment promises it raises only Rejected or
    # Faraday::Error. A URI error escaping that set is what turns a problem with
    # one attachment into a problem for the whole RUN.
    it "translates a URI error from the transport into Rejected" do
      connection = instance_double(Faraday::Connection)
      allow(connection).to receive(:get).and_raise(URI::InvalidURIError, "bad URI(is not URI?)")

      expect { described_class.new(connection: connection).call(attachment_start_url) }
        .to raise_error(described_class::Rejected, /url could not be requested/)
    end
  end

  # The size limit lives HERE, next to the allowlist: a check not applied
  # at BOTH download sites is only a suggestion. FetchBillsService#download_pdf,
  # feeding mutool and tesseract, lacked it.
  describe "size cap" do
    it "rejects a response whose advertised Content-Length is over the cap" do
      stub_request(:get, attachment_start_url).to_return(
        status: 200,
        body: "%PDF-1.4 small body, enormous claim",
        headers: {"Content-Length" => (512 * 1024 * 1024).to_s}
      )

      expect { attachment_fetcher.call(attachment_start_url) }
        .to raise_error(described_class::TooLarge, /advertises .* over the .*-byte cap/)
    end

    it "rejects an over-cap body that advertised no Content-Length" do
      stub_const("#{described_class}::MAX_ATTACHMENT_BYTES", 16)
      stub_request(:get, attachment_start_url).to_return(status: 200, body: "%PDF-1.4 well over sixteen bytes")

      expect { attachment_fetcher.call(attachment_start_url) }
        .to raise_error(described_class::TooLarge, /passed the 16-byte cap/)
    end

    it "raises TooLarge as a Rejected, so both callers' existing rescues cover it" do
      expect(described_class::TooLarge).to be < described_class::Rejected
    end

    it "leaves an at-cap body alone" do
      stub_const("#{described_class}::MAX_ATTACHMENT_BYTES", 11)
      stub_request(:get, attachment_start_url).to_return(status: 200, body: "%PDF-1.4 ok")

      expect(attachment_fetcher.call(attachment_start_url).body).to eq("%PDF-1.4 ok")
    end

    # Refusing mid-body means abandoning a response the transport was part
    # way through. The connection is shared across every attachment, so
    # leaving it unusable would take the whole bill down.
    it "leaves the connection usable for the next attachment after refusing one" do
      other = "https://baltimore.legistar1.com/baltimore/attachments/2.pdf"
      stub_const("#{described_class}::MAX_ATTACHMENT_BYTES", 16)
      stub_request(:get, attachment_start_url).to_return(status: 200, body: "%PDF-1.4 well over sixteen bytes")
      stub_request(:get, other).to_return(status: 200, body: "%PDF-1.4 ok")

      expect { attachment_fetcher.call(attachment_start_url) }.to raise_error(described_class::TooLarge)

      expect(attachment_fetcher.call(other).body).to eq("%PDF-1.4 ok")
    end

    it "does not size-check a redirect hop, only the terminal response" do
      hop = "https://baltimore.legistar1.com/cdn/1.pdf"
      stub_const("#{described_class}::MAX_ATTACHMENT_BYTES", 32)
      stub_request(:get, attachment_start_url).to_return(
        status: 302,
        body: "a redirect body longer than the cap, which is not the payload",
        headers: {"Location" => hop}
      )
      stub_request(:get, hop).to_return(status: 200, body: "%PDF-1.4 moved")

      expect(attachment_fetcher.call(attachment_start_url).body).to eq("%PDF-1.4 moved")
    end
  end

  describe "elapsed time ceiling" do
    # @lat: [[download-bounds#Download bounds]]
    it "raises TooSlow as a Rejected subclass, not a Faraday or Timeout error" do
      expect(described_class::TooSlow).to be < described_class::Rejected
      expect(described_class::TooSlow).not_to be < Faraday::Error
      expect(described_class::TooSlow).not_to be < Timeout::Error
    end

    it "rejects a single-hop download that dribbles bytes slower than the elapsed ceiling" do
      current_time = 1_000.0
      allow(Process).to receive(:clock_gettime).and_call_original
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { current_time }

      stub_request(:get, attachment_start_url).to_return do
        current_time += 35.0
        {status: 200, body: "%PDF-1.4 slow dribble"}
      end

      expect { attachment_fetcher.call(attachment_start_url) }
        .to raise_error(described_class::TooSlow, /ceiling|elapsed/i)
    end

    it "enforces the elapsed ceiling across the whole redirect walk rather than resetting per hop" do
      current_time = 1_000.0
      allow(Process).to receive(:clock_gettime).and_call_original
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { current_time }

      hop2 = "https://baltimore.legistar1.com/cdn/hop2.pdf"
      hop3 = "https://baltimore.legistar1.com/cdn/hop3.pdf"

      stub_request(:get, attachment_start_url).to_return do
        current_time += 20.0
        {status: 302, headers: {"Location" => hop2}}
      end
      stub_request(:get, hop2).to_return do
        current_time += 15.0
        {status: 302, headers: {"Location" => hop3}}
      end
      probe_hop3 = stub_request(:get, hop3).to_return(status: 200, body: "%PDF-1.4 hop3")

      expect { attachment_fetcher.call(attachment_start_url) }
        .to raise_error(described_class::TooSlow, /ceiling|elapsed/i)

      expect(probe_hop3).not_to have_been_requested
    end

    it "allows a download completing within the elapsed ceiling to succeed" do
      current_time = 1_000.0
      allow(Process).to receive(:clock_gettime).and_call_original
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { current_time }

      stub_request(:get, attachment_start_url).to_return do
        current_time += 2.0
        {status: 200, body: "%PDF-1.4 healthy"}
      end

      response = attachment_fetcher.call(attachment_start_url)
      expect(response.status).to eq(200)
      expect(response.body).to eq("%PDF-1.4 healthy")
    end

    it "proves elapsed refusal is not retried by asserting connection request was made strictly 1 time" do
      current_time = 1_000.0
      allow(Process).to receive(:clock_gettime).and_call_original
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { current_time }

      req_stub = stub_request(:get, attachment_start_url).to_return do
        current_time += 35.0
        {status: 200, body: "%PDF-1.4 slow"}
      end

      expect { attachment_fetcher.call(attachment_start_url) }
        .to raise_error(described_class::TooSlow)

      expect(req_stub).to have_been_made.times(1)
    end
  end
end
