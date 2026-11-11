# frozen_string_literal: true

require "rails_helper"

# @lat: [[legistar-detail-url-resolution#Architectural resolution service]]
RSpec.describe Legistar::DetailUrlResolver do
  describe ".resolve" do
    it "delegates to a new instance and returns the resolved URL" do
      host = "baltimore.legistar.com"
      matter_id = 10599
      gateway_url = "https://#{host}/Gateway.aspx"
      relative_destination = "/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570"
      expected_url = "https://#{host}#{relative_destination}"

      stub_request(:head, gateway_url)
        .with(query: {"M" => "L", "ID" => "10599"})
        .to_return(status: 302, headers: {"Location" => relative_destination})

      expect(described_class.resolve(matter_id)).to eq(expected_url)
    end
  end

  describe "#resolve" do
    context "with valid matter_id and 302 redirect response" do
      it "resolves relative Location to absolute canonical URL" do
        host = "baltimore.legistar.com"
        matter_id = 10599
        gateway_url = "https://#{host}/Gateway.aspx"
        relative_destination = "/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570"
        expected_url = "https://#{host}#{relative_destination}"

        resolver = described_class.new(host: host)
        stub_request(:head, gateway_url)
          .with(query: {"M" => "L", "ID" => "10599"})
          .to_return(status: 302, headers: {"Location" => relative_destination})

        expect(resolver.resolve(matter_id)).to eq(expected_url)
      end

      it "accepts String matter_id and coerces safely" do
        host = "baltimore.legistar.com"
        gateway_url = "https://#{host}/Gateway.aspx"
        relative_destination = "/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570"
        expected_url = "https://#{host}#{relative_destination}"

        resolver = described_class.new(host: host)
        stub_request(:head, gateway_url)
          .with(query: {"M" => "L", "ID" => "10599"})
          .to_return(status: 302, headers: {"Location" => relative_destination})

        expect(resolver.resolve(" 10599 \n")).to eq(expected_url)
      end

      it "handles already absolute Location header" do
        host = "baltimore.legistar.com"
        matter_id = 10599
        gateway_url = "https://#{host}/Gateway.aspx"
        relative_destination = "/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570"
        expected_url = "https://#{host}#{relative_destination}"

        resolver = described_class.new(host: host)
        stub_request(:head, gateway_url)
          .with(query: {"M" => "L", "ID" => "10599"})
          .to_return(status: 302, headers: {"Location" => expected_url})

        expect(resolver.resolve(matter_id)).to eq(expected_url)
      end

      it "supports 301 and 303 redirect status codes" do
        host = "baltimore.legistar.com"
        matter_id = 10599
        gateway_url = "https://#{host}/Gateway.aspx"
        relative_destination = "/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570"
        expected_url = "https://#{host}#{relative_destination}"

        resolver = described_class.new(host: host)
        stub_request(:head, gateway_url)
          .with(query: {"M" => "L", "ID" => "10599"})
          .to_return(status: 301, headers: {"Location" => relative_destination})

        expect(resolver.resolve(matter_id)).to eq(expected_url)
      end

      it "supports GET requests when configured" do
        host = "baltimore.legistar.com"
        matter_id = 10599
        gateway_url = "https://#{host}/Gateway.aspx"
        relative_destination = "/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570"
        expected_url = "https://#{host}#{relative_destination}"

        get_resolver = described_class.new(host: host, http_method: :get)
        stub_request(:get, gateway_url)
          .with(query: {"M" => "L", "ID" => "10599"})
          .to_return(status: 302, headers: {"Location" => relative_destination})

        expect(get_resolver.resolve(matter_id)).to eq(expected_url)
      end

      it "caches successful resolutions in-memory on the instance" do
        host = "baltimore.legistar.com"
        matter_id = 10599
        gateway_url = "https://#{host}/Gateway.aspx"
        relative_destination = "/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570"
        expected_url = "https://#{host}#{relative_destination}"

        resolver = described_class.new(host: host)
        stub = stub_request(:head, gateway_url)
          .with(query: {"M" => "L", "ID" => "10599"})
          .to_return(status: 302, headers: {"Location" => relative_destination})

        expect(resolver.resolve(matter_id)).to eq(expected_url)
        expect(resolver.resolve(matter_id)).to eq(expected_url)
        expect(stub).to have_been_requested.once
      end
    end

    context "when response is non-redirect (failure modes)" do
      it "returns nil and logs info on HTTP 200 OK (unavailable record)" do
        host = "baltimore.legistar.com"
        gateway_url = "https://#{host}/Gateway.aspx"

        resolver = described_class.new(host: host)
        stub_request(:head, gateway_url)
          .with(query: {"M" => "L", "ID" => "99999999"})
          .to_return(status: 200, body: "This record is currently unavailable.")

        expect(SwayLogging).to receive(:info).with(/non-redirect response status=200/)
        expect(resolver.resolve(99999999)).to be_nil
      end

      it "returns nil and logs info on HTTP 404 Not Found" do
        host = "baltimore.legistar.com"
        matter_id = 10599
        gateway_url = "https://#{host}/Gateway.aspx"

        resolver = described_class.new(host: host)
        stub_request(:head, gateway_url)
          .with(query: {"M" => "L", "ID" => "10599"})
          .to_return(status: 404)

        expect(SwayLogging).to receive(:info).with(/non-redirect response status=404/)
        expect(resolver.resolve(matter_id)).to be_nil
      end

      it "returns nil and logs warning when 302 is missing Location header" do
        host = "baltimore.legistar.com"
        matter_id = 10599
        gateway_url = "https://#{host}/Gateway.aspx"

        resolver = described_class.new(host: host)
        stub_request(:head, gateway_url)
          .with(query: {"M" => "L", "ID" => "10599"})
          .to_return(status: 302, headers: {"Location" => ""})

        expect(SwayLogging).to receive(:warn).with(/missing Location header/)
        expect(resolver.resolve(matter_id)).to be_nil
      end

      it "returns nil and logs warning when redirect destination is not LegislationDetail" do
        host = "baltimore.legistar.com"
        matter_id = 10599
        gateway_url = "https://#{host}/Gateway.aspx"

        resolver = described_class.new(host: host)
        stub_request(:head, gateway_url)
          .with(query: {"M" => "L", "ID" => "10599"})
          .to_return(status: 302, headers: {"Location" => "/Default.aspx"})

        expect(SwayLogging).to receive(:warn).with(/unexpected redirect destination/)
        expect(resolver.resolve(matter_id)).to be_nil
      end

      it "returns nil and logs warning when redirect destination host is unauthorized" do
        host = "baltimore.legistar.com"
        matter_id = 10599
        gateway_url = "https://#{host}/Gateway.aspx"

        resolver = described_class.new(host: host)
        stub_request(:head, gateway_url)
          .with(query: {"M" => "L", "ID" => "10599"})
          .to_return(
            status: 302,
            headers: {"Location" => "https://evil.com/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570"}
          )

        expect(SwayLogging).to receive(:warn).with(/unexpected redirect destination/)
        expect(resolver.resolve(matter_id)).to be_nil
      end

      it "returns nil and logs warning on protocol-relative redirect to an external host" do
        host = "baltimore.legistar.com"
        matter_id = 10599
        gateway_url = "https://#{host}/Gateway.aspx"
        proto_rel_destination = "//attacker.com/LegislationDetail.aspx?ID=1&GUID=2"

        resolver = described_class.new(host: host)
        stub_request(:head, gateway_url)
          .with(query: {"M" => "L", "ID" => "10599"})
          .to_return(status: 302, headers: {"Location" => proto_rel_destination})

        expect(SwayLogging).to receive(:warn).with(/unexpected redirect destination/)
        expect(resolver.resolve(matter_id)).to be_nil
      end

      it "returns nil and logs warning when redirect destination uses insecure http scheme" do
        host = "baltimore.legistar.com"
        matter_id = 10599
        gateway_url = "https://#{host}/Gateway.aspx"
        http_destination = "http://baltimore.legistar.com/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570"

        resolver = described_class.new(host: host)
        stub_request(:head, gateway_url)
          .with(query: {"M" => "L", "ID" => "10599"})
          .to_return(status: 302, headers: {"Location" => http_destination})

        expect(SwayLogging).to receive(:warn).with(/unexpected redirect destination/)
        expect(resolver.resolve(matter_id)).to be_nil
      end

      it "returns nil and logs warning when redirect destination contains GUID= but lacks ID=" do
        host = "baltimore.legistar.com"
        matter_id = 10599
        gateway_url = "https://#{host}/Gateway.aspx"
        missing_id_destination = "/LegislationDetail.aspx?GUID=44D47DEC-EC78-4AD0-86B9-B02879001570"

        resolver = described_class.new(host: host)
        stub_request(:head, gateway_url)
          .with(query: {"M" => "L", "ID" => "10599"})
          .to_return(status: 302, headers: {"Location" => missing_id_destination})

        expect(SwayLogging).to receive(:warn).with(/unexpected redirect destination/)
        expect(resolver.resolve(matter_id)).to be_nil
      end

      it "returns nil and logs warning when redirect destination contains ID= but lacks GUID=" do
        host = "baltimore.legistar.com"
        matter_id = 10599
        gateway_url = "https://#{host}/Gateway.aspx"
        missing_guid_destination = "/LegislationDetail.aspx?ID=8135417"

        resolver = described_class.new(host: host)
        stub_request(:head, gateway_url)
          .with(query: {"M" => "L", "ID" => "10599"})
          .to_return(status: 302, headers: {"Location" => missing_guid_destination})

        expect(SwayLogging).to receive(:warn).with(/unexpected redirect destination/)
        expect(resolver.resolve(matter_id)).to be_nil
      end

      it "returns nil for persistent HTTP 500 and rejects XSS in GUID, non-numeric ID, or embedded userinfo credentials" do
        host = "baltimore.legistar.com"
        matter_id = 10599
        gateway_url = "https://#{host}/Gateway.aspx"
        resolver = described_class.new(host: host)

        stub_request(:head, gateway_url)
          .with(query: {"M" => "L", "ID" => "10599"})
          .to_return(status: 500, headers: {})
        expect(SwayLogging).to receive(:info).with(/non-redirect response status=500/)
        expect(resolver.resolve(matter_id)).to be_nil

        [
          "/LegislationDetail.aspx?ID=8135417&GUID=<script>alert(1)</script>",
          "/LegislationDetail.aspx?ID=8135417abc&GUID=AAAA-1111",
          "https://admin:secret@baltimore.legistar.com/LegislationDetail.aspx?ID=8135417&GUID=AAAA-1111"
        ].each do |bad_location|
          stub_request(:head, gateway_url)
            .with(query: {"M" => "L", "ID" => "10599"})
            .to_return(status: 302, headers: {"Location" => bad_location})
          expect(SwayLogging).to receive(:warn).with(/unexpected redirect destination/)
          expect(resolver.resolve(matter_id)).to be_nil
        end
      end
    end

    context "with transport and network failures" do
      it "returns nil and logs warning on Faraday::TimeoutError" do
        host = "baltimore.legistar.com"
        matter_id = 10599
        gateway_url = "https://#{host}/Gateway.aspx"

        resolver = described_class.new(host: host)
        stub_request(:head, gateway_url)
          .with(query: {"M" => "L", "ID" => "10599"})
          .to_raise(Faraday::TimeoutError.new("execution expired"))

        expect(SwayLogging).to receive(:warn).with(/transport error.*Faraday::TimeoutError/)
        expect(resolver.resolve(matter_id)).to be_nil
      end

      it "returns nil and logs warning on Faraday::ConnectionFailed" do
        host = "baltimore.legistar.com"
        matter_id = 10599
        gateway_url = "https://#{host}/Gateway.aspx"

        resolver = described_class.new(host: host)
        stub_request(:head, gateway_url)
          .with(query: {"M" => "L", "ID" => "10599"})
          .to_raise(Faraday::ConnectionFailed.new("Connection refused"))

        expect(SwayLogging).to receive(:warn).with(/transport error.*Faraday::ConnectionFailed/)
        expect(resolver.resolve(matter_id)).to be_nil
      end
    end

    context "with transient retryable errors and retry middleware" do
      it "retries transient HTTP 503 and resolves canonical URL on subsequent redirect" do
        host = "baltimore.legistar.com"
        matter_id = 10599
        gateway_url = "https://#{host}/Gateway.aspx"
        relative_destination = "/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570"
        expected_url = "https://#{host}#{relative_destination}"

        resolver = described_class.new(host: host)
        stub_request(:head, gateway_url)
          .with(query: {"M" => "L", "ID" => "10599"})
          .to_return(status: 503, headers: {})
          .then
          .to_return(status: 302, headers: {"Location" => relative_destination})

        expect(resolver.resolve(matter_id)).to eq(expected_url)
      end

      it "retries transient Faraday::ConnectionFailed and resolves canonical URL on subsequent redirect" do
        host = "baltimore.legistar.com"
        matter_id = 10599
        gateway_url = "https://#{host}/Gateway.aspx"
        relative_destination = "/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570"
        expected_url = "https://#{host}#{relative_destination}"

        resolver = described_class.new(host: host)
        stub_request(:head, gateway_url)
          .with(query: {"M" => "L", "ID" => "10599"})
          .to_raise(Faraday::ConnectionFailed.new("connection reset"))
          .then
          .to_return(status: 302, headers: {"Location" => relative_destination})

        expect(resolver.resolve(matter_id)).to eq(expected_url)
      end

      it "returns nil and logs when retries are exhausted on 503" do
        host = "baltimore.legistar.com"
        matter_id = 10599
        gateway_url = "https://#{host}/Gateway.aspx"

        resolver = described_class.new(host: host)
        stub_request(:head, gateway_url)
          .with(query: {"M" => "L", "ID" => "10599"})
          .to_return(status: 503, headers: {})

        expect(SwayLogging).to receive(:info).with(/non-redirect response status=503/)
        expect(resolver.resolve(matter_id)).to be_nil
      end

      it "includes :head in RETRY_METHODS and RETRY_OPTIONS" do
        expect(described_class::RETRY_METHODS).to include(:head)
        expect(described_class::RETRY_OPTIONS[:methods]).to include(:head)
      end
    end

    context "with invalid input parameters" do
      it "returns nil for nil matter_id without issuing HTTP request" do
        resolver = described_class.new(host: "baltimore.legistar.com")
        expect(SwayLogging).to receive(:warn).with(/invalid matter_id: nil/)
        expect(resolver.resolve(nil)).to be_nil
      end

      it "returns nil for non-numeric String matter_id" do
        resolver = described_class.new(host: "baltimore.legistar.com")
        expect(SwayLogging).to receive(:warn).with(/invalid matter_id: "abc"/)
        expect(resolver.resolve("abc")).to be_nil
      end

      it "returns nil for negative integer matter_id" do
        resolver = described_class.new(host: "baltimore.legistar.com")
        expect(SwayLogging).to receive(:warn).with(/invalid matter_id: -5/)
        expect(resolver.resolve(-5)).to be_nil
      end

      it "returns nil for zero matter_id" do
        resolver = described_class.new(host: "baltimore.legistar.com")
        expect(SwayLogging).to receive(:warn).with(/invalid matter_id: 0/)
        expect(resolver.resolve(0)).to be_nil
      end

      it "returns nil for matter_id exceeding ID_MAX" do
        resolver = described_class.new(host: "baltimore.legistar.com")
        too_large = (2**31)
        expect(SwayLogging).to receive(:warn).with(/invalid matter_id: #{too_large}/)
        expect(resolver.resolve(too_large)).to be_nil
      end

      it "accepts boundary ID_MAX value ((2**31) - 1)" do
        host = "baltimore.legistar.com"
        max_id = (2**31) - 1
        gateway_url = "https://#{host}/Gateway.aspx"
        relative_destination = "/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570"

        resolver = described_class.new(host: host)
        stub_request(:head, gateway_url)
          .with(query: {"M" => "L", "ID" => max_id.to_s})
          .to_return(status: 302, headers: {"Location" => relative_destination})

        expect(resolver.resolve(max_id)).to eq("https://#{host}#{relative_destination}")
      end

      it "returns nil for host not matching Legistar host allowlist" do
        malicious_resolver = described_class.new(host: "evil.com")
        expect(SwayLogging).to receive(:warn).with(/disallowed host: "evil.com"/)
        expect(malicious_resolver.resolve(10599)).to be_nil
      end
    end
  end
end
