# frozen_string_literal: true

require "rails_helper"

RSpec.describe Legistar::Client do
  subject(:client) { described_class.new }

  let(:base) { "https://webapi.legistar.com/v1/baltimore" }

  def stub_legistar(path, body:, status: 200, query: nil)
    stub = stub_request(:get, "#{base}/#{path}")
    stub = stub.with(query: query) if query
    stub.to_return(status: status, body: body, headers: {"Content-Type" => "application/json"})
  end

  describe "#get" do
    it "hits /v1/<client>/<resource> and parses the JSON array body" do
      stub_legistar("Matters", body: [{"MatterId" => 1}, {"MatterId" => 2}].to_json)

      result = client.get("Matters")

      expect(result).to eq([{"MatterId" => 1}, {"MatterId" => 2}])
    end

    it "encodes symbol OData options with a $ prefix and drops nils" do
      req = stub_legistar(
        "Matters",
        query: {"$top" => "5", "$orderby" => "MatterId desc", "$filter" => "MatterTypeName eq 'Ordinance'"},
        body: "[]"
      )

      client.get("Matters", top: 5, orderby: "MatterId desc", filter: "MatterTypeName eq 'Ordinance'", skip: nil)

      expect(req).to have_been_requested
    end

    # This class promises string keys pass through with NO $ added —
    # Legistar's EventItems Attachments flag takes no $ prefix, and a live
    # call proved the $-prefixed spelling returns HTTP 400.
    it "passes a string key through UNPREFIXED (no $ added) via #get_raw" do
      req = stub_legistar("Events/5065/EventItems", query: {"Attachments" => "1"}, body: "[]")

      client.get_raw("Events/5065/EventItems", "Attachments" => 1)

      expect(req).to have_been_requested
    end

    it "raises HttpError carrying status + path on a non-2xx response" do
      stub_legistar("Matters/9", body: "nope", status: 500)

      expect { client.get("Matters/9") }.to raise_error(Legistar::Client::HttpError) do |error|
        expect(error.status).to eq(500)
        expect(error.path).to eq("/v1/baltimore/Matters/9")
      end
    end

    it "raises ParseError (a subclass of Error) on a non-JSON 2xx body" do
      stub_legistar("Matters", body: "<html>not json</html>")

      # ParseError is a separate class from a plain transport Error so that
      # callers such as FetchBillsService can shrug off a garbage success body
      # without also swallowing network failures.
      expect(Legistar::Client::ParseError).to be < Legistar::Client::Error
      expect { client.get("Matters") }.to raise_error(Legistar::Client::ParseError, /non-JSON/)
    end

    # #parse used to open with a dead branch, since #get_raw scrubs the
    # body to a String first. If JSON middleware were ever mounted, that
    # branch would misreport good JSON as an error.
    describe "a connection whose middleware already decoded the body (A1-WR-04)" do
      def json_decoded_connection(body)
        Faraday.new do |conn|
          conn.adapter :test do |stub|
            stub.get("/v1/baltimore/Matters") { [200, {"Content-Type" => "application/json"}, body] }
          end
        end
      end

      # THE CASE THAT HAD TO FAIL FIRST.
      it "returns a pre-decoded Array unchanged instead of raising ParseError" do
        rows = [{"MatterId" => 1}, {"MatterId" => 2}]
        client = described_class.new(connection: json_decoded_connection(rows))

        expect(client.get("Matters")).to eq(rows)
      end

      it "returns a pre-decoded Hash unchanged instead of raising ParseError" do
        row = {"MatterId" => 10122, "MatterFile" => "25-0064"}
        client = described_class.new(connection: json_decoded_connection(row))

        expect(client.get("Matters")).to eq(row)
      end

      # The error path must keep working on such a connection too, and must keep
      # handing HttpError a String rather than the decoded object.
      it "still raises HttpError with a String body when a decoded body arrives non-2xx" do
        conn = Faraday.new do |c|
          c.adapter :test do |stub|
            stub.get("/v1/baltimore/Matters") { [500, {}, {"Error" => "boom"}] }
          end
        end

        expect { described_class.new(connection: conn).get("Matters") }
          .to raise_error(Legistar::Client::HttpError, /HTTP 500/)
      end
    end

    # Making bytes valid UTF-8 at the boundary covered mutool/txt but not
    # this: a badly encoded title reaches #downcase and JSON serialize,
    # neither a BillProcessingError, so both kill the run.
    describe "invalid UTF-8 in a 2xx body (A2-WR-01)" do
      let(:dirty_legistar_body) { %([{"MatterAttachmentId":975,"MatterAttachmentName":"caf\xC3\x28e Testimony 25-0064","MatterAttachmentFileName":"caf\xC3\x28e.pdf"}]).b }

      it "returns strings the regexp engine accepts" do
        stub_legistar("Matters/1/Attachments", body: dirty_legistar_body)

        name = client.get("Matters/1/Attachments").first["MatterAttachmentName"]

        expect(name.valid_encoding?).to be(true)
        expect { name.downcase }.not_to raise_error
        expect { name.match?(/testimony/i) }.not_to raise_error
        expect(name).to include("Testimony 25-0064")
      end

      it "returns strings JSON.generate can re-serialize (the coder: JSON seam)" do
        stub_legistar("Matters/1/Attachments", body: dirty_legistar_body)

        parsed = client.get("Matters/1/Attachments")

        expect { JSON.generate(parsed) }.not_to raise_error
        expect { JSON.pretty_generate(parsed) }.not_to raise_error
      end

      it "leaves a correctly-encoded multibyte body byte-identical" do
        clean = %([{"MatterAttachmentName":"Ordinance – “Small Box” café"}])
        stub_legistar("Matters/2/Attachments", body: clean)

        name = client.get("Matters/2/Attachments").first["MatterAttachmentName"]

        expect(name).to eq("Ordinance – “Small Box” café")
      end
    end

    # The success-path cleanup missed the error path: a raw body handed to
    # HttpError raised Encoding::CompatibilityError from ASCII-8BIT bytes —
    # an EncodingError no rescue catches, killing the run.
    describe "non-2xx bodies carrying non-ASCII bytes (A3-CR-01)" do
      it "raises HttpError, not Encoding::CompatibilityError, on a BINARY body with valid high bytes" do
        stub_legistar("Matters/9", body: "<html>Bad Gateway \xE2\x80\x94 upstream</html>".b, status: 502)

        expect { client.get("Matters/9") }.to raise_error(Legistar::Client::HttpError) do |error|
          expect(error.status).to eq(502)
          expect(error.message).to include("Bad Gateway")
        end
      end

      it "raises HttpError with a valid-UTF-8, JSON-serializable message on an invalid-byte body" do
        stub_legistar("Matters/9", body: "<html>caf\xC3\x28 error</html>".b, status: 500)

        expect { client.get("Matters/9") }.to raise_error(Legistar::Client::HttpError) do |error|
          # The message reaches bill_run.error_message and the stage_results
          # JSON column; JSON.generate raises on invalid UTF-8.
          expect(error.message.valid_encoding?).to be(true)
          expect { JSON.generate({error: error.message}) }.not_to raise_error
        end
      end
    end
  end

  describe "#get_all (pagination)" do
    it "walks $skip until a short page and concatenates every row" do
      stub_legistar("Matters", query: {"$top" => "2", "$skip" => "0"}, body: [{"id" => 1}, {"id" => 2}].to_json)
      stub_legistar("Matters", query: {"$top" => "2", "$skip" => "2"}, body: [{"id" => 3}].to_json)

      expect(client.get_all("Matters", page_size: 2).pluck("id")).to eq([1, 2, 3])
    end

    it "stops at max_pages even if every page is full" do
      stub_legistar("Matters", query: hash_including("$top" => "1"), body: [{"id" => 9}].to_json)

      expect(client.get_all("Matters", page_size: 1, max_pages: 3).size).to eq(3)
    end
  end

  # Only the wrappers that something actually calls were kept: matters,
  # matter_attachments, matter_histories, person and body_office_records.
  describe "typed convenience methods" do
    it "matter_histories requests /Matters/:id/Histories" do
      stub_legistar("Matters/9928/Histories", body: "[]")
      expect(client.matter_histories(9928)).to eq([])
    end

    it "matter_attachments requests /Matters/:id/Attachments" do
      stub_legistar("Matters/9928/Attachments", body: "[]")
      expect(client.matter_attachments(9928)).to eq([])
    end

    it "accepts a digit string id" do
      stub_legistar("Matters/9928/Histories", body: "[]")
      expect(client.matter_histories("9928")).to eq([])
    end

    it "maps the kept sub-resource wrappers to the right Legistar paths" do
      cases = {
        "Matters" => ["[]", -> { client.matters }],
        "Persons/104" => ["{}", -> { client.person(104) }],
        "Bodies/3/OfficeRecords" => ["[]", -> { client.body_office_records(3) }]
      } #: Hash[String, [String, ^() -> untyped]]
      cases.each do |path, (body, call)|
        req = stub_legistar(path, body: body)
        call.call
        expect(req).to have_been_requested
      end
    end
  end

  describe "path id coercion" do
    it "rejects a non-digit string (no path injection)" do
      expect { client.person("9928/Histories?x=1") }.to raise_error(Legistar::Client::Error, /1-10 digits/)
    end

    it "rejects a non-positive id" do
      expect { client.person(0) }.to raise_error(Legistar::Client::Error, /positive integer/)
    end

    it "rejects a non-integer-coercible id" do
      expect { client.person(nil) }.to raise_error(Legistar::Client::Error, /Integer-coercible/)
    end
  end
end
