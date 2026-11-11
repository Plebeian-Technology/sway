# frozen_string_literal: true

require "rails_helper"

# Specs for TestimonyTextExtractor. Narrower than mupdf_extractor_spec.rb —
# no OCR fixtures, no TESSDATA_PREFIX setup. One mutool call in; text or
# ExtractionFailed out.
RSpec.describe TestimonyTextExtractor do
  describe "#call" do
    it "returns mutool stdout on success" do
      pdf_path = "/tmp/testimony_att_1.pdf"
      success = instance_double(Process::Status, success?: true)
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", pdf_path)
        .and_return(["extracted body", "", success])

      result = described_class.new(pdf_path).call

      expect(result).to eq("extracted body")
      expect(Sway::Subprocess).to have_received(:capture3).once
    end

    it "returns an empty string without raising when mutool succeeds with no text layer" do
      pdf_path = "/tmp/testimony_att_scanned.pdf"
      success = instance_double(Process::Status, success?: true)
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", pdf_path)
        .and_return(["", "", success])

      result = described_class.new(pdf_path).call

      expect(result).to eq("")
    end

    it "raises ExtractionFailed with a bounded stderr snippet when mutool exits non-zero" do
      pdf_path = "/tmp/testimony_att_2.pdf"
      failure = instance_double(Process::Status, success?: false, exitstatus: 1)
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", pdf_path)
        .and_return(["", "mutool: cannot open document: no such file", failure])

      expect { described_class.new(pdf_path).call }
        .to raise_error(TestimonyTextExtractor::ExtractionFailed, /mutool failed.*cannot open document/)
    end

    # Named for the bound and can't see it: delete [0, 500] and it stays
    # green. The truncation defends against OutputTooLarge — the error
    # column stays a snippet.
    it "cuts the stderr snippet at 500 characters" do
      pdf_path = "/tmp/testimony_att_flood.pdf"
      failure = instance_double(Process::Status, success?: false, exitstatus: 1)
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", pdf_path)
        .and_return(["", "e" * 5_000, failure])

      expect { described_class.new(pdf_path).call }
        .to raise_error(TestimonyTextExtractor::ExtractionFailed) { |error|
          expect(error.message).to include("e" * 500)
          expect(error.message).not_to include("e" * 501)
        }
    end

    it "invokes Sway::Subprocess.capture3 with 'mutool' as the first positional arg (no shell string)" do
      pdf_path = "/tmp/testimony_att_3.pdf"
      success = instance_double(Process::Status, success?: true)
      allow(Sway::Subprocess).to receive(:capture3).and_return(["body", "", success])

      described_class.new(pdf_path).call

      expect(Sway::Subprocess).to have_received(:capture3)
        .with("mutool", "draw", "-F", "txt", pdf_path)
    end

    # Nothing checks mutool is installed on this path — the extractor skips
    # preflight! — so a missing binary surfaces as Errno::ENOENT. Translating
    # SystemCallError keeps the failure to one attachment.
    it "raises ExtractionFailed, not Errno::ENOENT, when the mutool binary is absent" do
      pdf_path = "/tmp/testimony_att_4.pdf"
      allow(Sway::Subprocess).to receive(:capture3)
        .and_raise(Errno::ENOENT)

      expect { described_class.new(pdf_path).call }
        .to raise_error(TestimonyTextExtractor::ExtractionFailed, /mutool unavailable.*ENOENT/)
    end

    # A malformed PDF that sends mutool spinning used to block fetch_hearings
    # forever, twice over (attempt_extraction retries once). TimedOut needs
    # the same translation SystemCallError gets.
    it "raises ExtractionFailed, not TimedOut, when mutool outruns its deadline" do
      pdf_path = "/tmp/testimony_att_hang.pdf"
      allow(Sway::Subprocess).to receive(:capture3)
        .and_raise(Sway::Subprocess::TimedOut, "mutool exceeded 300s and was killed")

      expect { described_class.new(pdf_path).call }
        .to raise_error(TestimonyTextExtractor::ExtractionFailed, /timed out/i)
    end

    # Sway::Subprocess used to cap runtime but not output SIZE. Now
    # OutputTooLarge needs the same StandardError translation, or an
    # oversized run escapes as a StageError.
    it "raises ExtractionFailed, not OutputTooLarge, when mutool floods its output cap" do
      pdf_path = "/tmp/testimony_att_flood.pdf"
      allow(Sway::Subprocess).to receive(:capture3)
        .and_raise(Sway::Subprocess::OutputTooLarge, "mutool produced more than 262144 bytes on stderr and was killed")

      expect { described_class.new(pdf_path).call }
        .to raise_error(TestimonyTextExtractor::ExtractionFailed, /output too large/i)
    end

    it "raises ExtractionFailed when the mutool binary is not executable" do
      pdf_path = "/tmp/testimony_att_5.pdf"
      allow(Sway::Subprocess).to receive(:capture3)
        .and_raise(Errno::EACCES)

      expect { described_class.new(pdf_path).call }
        .to raise_error(TestimonyTextExtractor::ExtractionFailed, /mutool unavailable.*EACCES/)
    end

    # mutool prints whatever the text layer decodes to; broken encoding gives
    # invalid UTF-8 nobody checked, until a downstream gsub raised
    # ArgumentError. Scrubbed here instead.
    it "scrubs invalid UTF-8 out of mutool stdout while preserving the legible text" do
      pdf_path = "/tmp/testimony_att_bad_bytes.pdf"
      success = instance_double(Process::Status, success?: true)
      invalid = (+"ACME Coalition supports \xC3\x28 the bill.").force_encoding(Encoding::UTF_8)
      expect(invalid.valid_encoding?).to be(false)
      allow(Sway::Subprocess).to receive(:capture3).and_return([invalid, "", success])

      result = described_class.new(pdf_path).call

      expect(result.valid_encoding?).to be(true)
      expect(result).to include("ACME Coalition supports")
      expect(result).to include("the bill.")
      expect { result.gsub(/`{3,}/, "'''") }.not_to raise_error
    end

    it "returns UTF-8 even when the subprocess hands back binary-encoded stdout" do
      pdf_path = "/tmp/testimony_att_binary.pdf"
      success = instance_double(Process::Status, success?: true)
      binary = (+"Plain testimony body.").force_encoding(Encoding::ASCII_8BIT)
      allow(Sway::Subprocess).to receive(:capture3).and_return([binary, "", success])

      result = described_class.new(pdf_path).call

      expect(result.encoding).to eq(Encoding::UTF_8)
      expect(result).to eq("Plain testimony body.")
    end

    it "leaves valid multibyte UTF-8 untouched" do
      pdf_path = "/tmp/testimony_att_multibyte.pdf"
      success = instance_double(Process::Status, success?: true)
      allow(Sway::Subprocess).to receive(:capture3).and_return(["Señora Núñez — testimonio “completo”.", "", success])

      result = described_class.new(pdf_path).call

      expect(result).to eq("Señora Núñez — testimonio “completo”.")
    end
  end

  describe "#call — remote extractor via pdf_extractor_url" do
    it "posts disable_ocr: true to /extract without calling Sway::Subprocess.capture3 and returns scrubbed text on 200 OK" do
      pdf_path = "/tmp/testimony_remote_1.pdf"
      remote_url = "http://pdf-extractor:8085"
      extract_endpoint = "#{remote_url}/extract"
      allow(Sway::Subprocess).to receive(:capture3)

      with_app_config(:legislation, pdf_extractor_url: "#{remote_url}/") do
        stub_request(:post, extract_endpoint)
          .with(
            body: {pdf_path: pdf_path, disable_ocr: true}.to_json,
            headers: {"Content-Type" => "application/json"}
          )
          .to_return(
            status: 200,
            headers: {"Content-Type" => "application/json"},
            body: {text: "Remote testimony body.", ocr_used: false, truncated: false}.to_json
          )

        result = described_class.new(pdf_path).call

        expect(result.valid_encoding?).to be(true)
        expect(result).to eq("Remote testimony body.")
        expect(Sway::Subprocess).not_to have_received(:capture3)
      end
    end

    it "returns an empty string without raising when the remote 200 OK response has empty text" do
      pdf_path = "/tmp/testimony_remote_scanned.pdf"
      remote_url = "http://pdf-extractor:8085"
      extract_endpoint = "#{remote_url}/extract"
      allow(Sway::Subprocess).to receive(:capture3)

      with_app_config(:legislation, pdf_extractor_url: remote_url) do
        stub_request(:post, extract_endpoint)
          .with(
            body: {pdf_path: pdf_path, disable_ocr: true}.to_json,
            headers: {"Content-Type" => "application/json"}
          )
          .to_return(
            status: 200,
            headers: {"Content-Type" => "application/json"},
            body: {text: "", ocr_used: false, truncated: false}.to_json
          )

        result = described_class.new(pdf_path).call

        expect(result).to eq("")
        expect(Sway::Subprocess).not_to have_received(:capture3)
      end
    end

    it "raises ExtractionFailed with message truncated to at most 500 characters on HTTP 500" do
      pdf_path = "/tmp/testimony_remote_500.pdf"
      remote_url = "http://pdf-extractor:8085"
      extract_endpoint = "#{remote_url}/extract"
      dirty_err = (+"mutool failed \xC3\x28 " + "x" * 600).force_encoding(Encoding::UTF_8)

      with_app_config(:legislation, pdf_extractor_url: remote_url) do
        stub_request(:post, extract_endpoint)
          .to_return(status: 500, body: dirty_err)

        message = begin
          described_class.new(pdf_path).call
          ""
        rescue TestimonyTextExtractor::ExtractionFailed => e
          e.message
        end

        expect(message.valid_encoding?).to be(true)
        expect(message.length).to be <= 500
        expect(message).to match(/remote pdf extractor failed \(HTTP 500\)/)
      end
    end

    it "raises ExtractionFailed with message truncated to at most 500 characters on Timeout::Error" do
      pdf_path = "/tmp/testimony_remote_timeout.pdf"
      remote_url = "http://pdf-extractor:8085"
      extract_endpoint = "#{remote_url}/extract"

      with_app_config(:legislation, pdf_extractor_url: remote_url) do
        stub_request(:post, extract_endpoint)
          .to_raise(Timeout::Error.new("execution expired " + "t" * 600))

        message = begin
          described_class.new(pdf_path).call
          ""
        rescue TestimonyTextExtractor::ExtractionFailed => e
          e.message
        end

        expect(message.valid_encoding?).to be(true)
        expect(message.length).to be <= 500
        expect(message).to match(/remote pdf extractor timed out/)
      end
    end

    it "raises ExtractionFailed with message truncated to at most 500 characters on Errno::ECONNREFUSED" do
      pdf_path = "/tmp/testimony_remote_connrefused.pdf"
      remote_url = "http://pdf-extractor:8085"
      extract_endpoint = "#{remote_url}/extract"

      with_app_config(:legislation, pdf_extractor_url: remote_url) do
        stub_request(:post, extract_endpoint)
          .to_raise(Errno::ECONNREFUSED.new("Connection refused " + "c" * 600))

        message = begin
          described_class.new(pdf_path).call
          ""
        rescue TestimonyTextExtractor::ExtractionFailed => e
          e.message
        end

        expect(message.valid_encoding?).to be(true)
        expect(message.length).to be <= 500
        expect(message).to match(/remote pdf extractor failed: ECONNREFUSED/)
      end
    end
  end
end
