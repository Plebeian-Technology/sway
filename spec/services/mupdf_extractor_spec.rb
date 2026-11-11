# frozen_string_literal: true

require "rails_helper"

# Specs for MupdfExtractor. Settled by earlier experiments:
# MIN_NATIVE_CHARS=50 sends to OCR, OCR_DPI=300 avoids smearing,
# TESSDATA_PREFIX must be set, and capture3 takes SEPARATE args.
module MupdfExtractorSpecHelpers
  NATIVE_PDF_PATH = Rails.root.join("spec", "fixtures", "files", "mupdf_extractor", "native.pdf").to_s
  IMAGE_PDF_PATH = Rails.root.join("spec", "fixtures", "files", "mupdf_extractor", "image_only.pdf").to_s
  # Unlike the two paths above, this one is a real PDF carrying a real text
  # layer, built by mutool from the recipe in the fixture directory's README.
  TEXT_LAYER_PDF_PATH = Rails.root.join("spec", "fixtures", "files", "mupdf_extractor", "text_layer.pdf").to_s
  # These specs replace mutool through Sway::Subprocess, so preflight! only
  # needs a directory with a .traineddata file, built under tmp/ rather
  # than relying on a system tesseract install.
  TESSDATA_DIR = Rails.root.join("tmp", "tessdata_fixture").to_s
  FileUtils.mkdir_p(TESSDATA_DIR)
  FileUtils.touch(File.join(TESSDATA_DIR, "eng.traineddata"))

  def stub_mutool(*args, stdout: "", stderr: "", success: true, exitstatus: 0)
    status = instance_double(Process::Status, success?: success, exitstatus: exitstatus)
    allow(Sway::Subprocess).to receive(:capture3)
      .with("mutool", *args)
      .and_return([stdout, stderr, status])
  end
end

RSpec.describe MupdfExtractor do
  include MupdfExtractorSpecHelpers

  describe "constants" do
    it "defines MIN_NATIVE_CHARS = 50 (spike-locked native-text threshold)" do
      expect(described_class::MIN_NATIVE_CHARS).to eq(50)
    end

    it "defines OCR_DPI = 300 (spike-locked render resolution)" do
      expect(described_class::OCR_DPI).to eq(300)
    end
  end

  describe "#initialize" do
    it "raises MissingTessdataError when TESSDATA_PREFIX is unset" do
      with_app_config(:legislation, tessdata_prefix: nil) do
        expect { described_class.new(MupdfExtractorSpecHelpers::NATIVE_PDF_PATH) }
          .to raise_error(MupdfExtractor::MissingTessdataError, /TESSDATA_PREFIX/)
      end
    end

    it "raises MissingTessdataError when TESSDATA_PREFIX is empty string" do
      with_app_config(:legislation, tessdata_prefix: "") do
        expect { described_class.new(MupdfExtractorSpecHelpers::NATIVE_PDF_PATH) }
          .to raise_error(MupdfExtractor::MissingTessdataError, /TESSDATA_PREFIX/)
      end
    end

    # The declaration's :string caster now handles this, not the call site:
    # a spaces-only value is blank, so it reads back nil here exactly
    # as an unset value does, rather than reaching File.directory?("   ")
    # and raising the "directory not found" message instead.
    it "raises MissingTessdataError when TESSDATA_PREFIX is spaces only" do
      with_app_config(:legislation, tessdata_prefix: "   ") do
        expect { described_class.new(MupdfExtractorSpecHelpers::NATIVE_PDF_PATH) }
          .to raise_error(MupdfExtractor::MissingTessdataError, /TESSDATA_PREFIX env var not set/)
      end
    end

    it "raises MissingTessdataError, naming the directory, when TESSDATA_PREFIX points nowhere" do
      with_app_config(:legislation, tessdata_prefix: "/nonexistent/tessdata/path") do
        expect { described_class.new(MupdfExtractorSpecHelpers::NATIVE_PDF_PATH) }
          .to raise_error(MupdfExtractor::MissingTessdataError, %r{directory "/nonexistent/tessdata/path" not found})
      end
    end

    it "raises MissingTessdataError when TESSDATA_PREFIX exists but holds no .traineddata file" do
      empty_dir = Rails.root.join("tmp", "tessdata_fixture_empty").to_s
      FileUtils.mkdir_p(empty_dir)
      FileUtils.rm_f(Dir.glob(File.join(empty_dir, "*")))

      with_app_config(:legislation, tessdata_prefix: empty_dir) do
        expect { described_class.new(MupdfExtractorSpecHelpers::NATIVE_PDF_PATH) }
          .to raise_error(MupdfExtractor::MissingTessdataError, /contains no \.traineddata files/)
      end
    end

    it "skips the local tessdata check when pdf_extractor_url is present" do
      with_app_config(:legislation, tessdata_prefix: nil, pdf_extractor_url: "http://pdf-extractor:8085") do
        expect { described_class.preflight! }.not_to raise_error
        expect { described_class.new(MupdfExtractorSpecHelpers::NATIVE_PDF_PATH) }.not_to raise_error
      end

      with_app_config(:legislation, tessdata_prefix: nil, pdf_extractor_url: "") do
        expect { described_class.preflight! }
          .to raise_error(MupdfExtractor::MissingTessdataError, /TESSDATA_PREFIX/)
        expect { described_class.new(MupdfExtractorSpecHelpers::NATIVE_PDF_PATH) }
          .to raise_error(MupdfExtractor::MissingTessdataError, /TESSDATA_PREFIX/)
      end
    end
  end

  describe "#call" do
    around do |example|
      with_app_config(:legislation, tessdata_prefix: MupdfExtractorSpecHelpers::TESSDATA_DIR) { example.run }
    end

    # @lat: [[testing-the-toolchain#One example lets the real converter run]]
    it "pulls the text layer out of a real PDF with mutool actually running" do
      result = described_class.new(MupdfExtractorSpecHelpers::TEXT_LAYER_PDF_PATH).call

      expect(result).to include("marker SWAY TEXT LAYER FIXTURE 5FLI9")
      # Plain text, and the first thing on the page. Asking only for the
      # marker somewhere in the result passes just as happily for mutool's
      # xhtml output, which carries the same words wrapped in markup.
      expect(result).to start_with("SWAY SYNTHETIC TEXT LAYER FIXTURE")
    end

    it "returns native text and does NOT invoke OCR when native output >= MIN_NATIVE_CHARS" do
      native_path = MupdfExtractorSpecHelpers::NATIVE_PDF_PATH
      native_text = "a" * 200 # comfortably over the 50-character threshold
      success = instance_double(Process::Status, success?: true)
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", native_path)
        .and_return([native_text, "", success])

      result = described_class.new(native_path).call

      expect(result).to eq(native_text)
      expect(Sway::Subprocess).to have_received(:capture3).once
      # Check the OCR path (ocr.txt) never ran.
      expect(Sway::Subprocess).not_to have_received(:capture3)
        .with("mutool", "draw", "-F", "ocr.txt", "-r", "300", anything)
    end

    it "falls back to OCR at 300 DPI when native output < MIN_NATIVE_CHARS" do
      image_path = MupdfExtractorSpecHelpers::IMAGE_PDF_PATH
      short_native = "abc" # 3 characters, under the 50-character threshold
      ocr_text = "x" * 5000
      success = instance_double(Process::Status, success?: true)
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", image_path)
        .and_return([short_native, "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "ocr.txt", "-r", "300", image_path)
        .and_return([ocr_text, "", success])

      result = described_class.new(image_path).call

      expect(result).to eq(ocr_text)
      expect(Sway::Subprocess).to have_received(:capture3)
        .with("mutool", "draw", "-F", "txt", image_path).once
      expect(Sway::Subprocess).to have_received(:capture3)
        .with("mutool", "draw", "-F", "ocr.txt", "-r", "300", image_path).once
    end

    it "invokes Sway::Subprocess.capture3 with positional args (no shell string, no command injection)" do
      native_path = MupdfExtractorSpecHelpers::NATIVE_PDF_PATH
      success = instance_double(Process::Status, success?: true)
      allow(Sway::Subprocess).to receive(:capture3).and_return(["a" * 100, "", success])

      described_class.new(native_path).call

      # Separate arguments: ("mutool", "draw", "-F", "txt", path), NOT one shell
      # string like "mutool draw -F txt #{path}". That is what stops a crafted
      # filename from running a command of its own.
      expect(Sway::Subprocess).to have_received(:capture3)
        .with("mutool", "draw", "-F", "txt", native_path)
    end

    it "raises ExtractionFailed with stderr included when mutool exits non-zero" do
      native_path = MupdfExtractorSpecHelpers::NATIVE_PDF_PATH
      stderr_msg = "mutool: cannot open document: no such file"
      failure = instance_double(Process::Status, success?: false, exitstatus: 1)
      allow(Sway::Subprocess).to receive(:capture3)
        .and_return(["", stderr_msg, failure])

      expect { described_class.new(native_path).call }
        .to raise_error(MupdfExtractor::ExtractionFailed, /mutool failed.*cannot open document/)
    end

    # The original report was about TestimonyTextExtractor, but this is the
    # OTHER mutool wrapper with the same unbounded Open3.capture3 call.
    it "raises ExtractionFailed, not TimedOut, when mutool outruns its deadline" do
      native_path = MupdfExtractorSpecHelpers::NATIVE_PDF_PATH
      allow(Sway::Subprocess).to receive(:capture3)
        .and_raise(Sway::Subprocess::TimedOut, "mutool exceeded 300s and was killed")

      expect { described_class.new(native_path).call }
        .to raise_error(MupdfExtractor::ExtractionFailed, /timed out/i)
    end

    # OutputTooLarge is an ordinary StandardError, like TimedOut. All three
    # subprocess sites here must convert it, not just the one a reviewer
    # noticed.
    it "raises ExtractionFailed, not OutputTooLarge, when mutool floods its output cap" do
      native_path = MupdfExtractorSpecHelpers::NATIVE_PDF_PATH
      allow(Sway::Subprocess).to receive(:capture3)
        .and_raise(Sway::Subprocess::OutputTooLarge, "mutool produced more than 262144 bytes on stderr and was killed")

      expect { described_class.new(native_path).call }
        .to raise_error(MupdfExtractor::ExtractionFailed, /output too large/i)
    end

    # TestimonyTextExtractor#run_mutool converts SystemCallError since
    # anything else becomes a run-killing StageError; this class never did,
    # at any of its three calls.
    it "raises ExtractionFailed, not Errno::ENOENT, when the mutool binary is absent" do
      native_path = MupdfExtractorSpecHelpers::NATIVE_PDF_PATH
      allow(Sway::Subprocess).to receive(:capture3).and_raise(Errno::ENOENT)

      expect { described_class.new(native_path).call }
        .to raise_error(MupdfExtractor::ExtractionFailed, /mutool unavailable.*ENOENT/)
    end

    it "raises ExtractionFailed when the mutool binary is not executable" do
      native_path = MupdfExtractorSpecHelpers::NATIVE_PDF_PATH
      allow(Sway::Subprocess).to receive(:capture3).and_raise(Errno::EACCES)

      expect { described_class.new(native_path).call }
        .to raise_error(MupdfExtractor::ExtractionFailed, /mutool unavailable.*EACCES/)
    end
  end

  # An earlier fix cleaned mutool's output in TestimonyTextExtractor but
  # not here — this class's output feeds source_present?, whose match?
  # raises ArgumentError on invalid bytes.
  describe "#call — invalid UTF-8 from the subprocess (B2-CR-01)" do
    around do |example|
      with_app_config(:legislation, tessdata_prefix: MupdfExtractorSpecHelpers::TESSDATA_DIR) { example.run }
    end

    it "scrubs native mutool stdout so the result survives String#present?" do
      native_path = MupdfExtractorSpecHelpers::NATIVE_PDF_PATH
      dirty = (+("Baltimore ordinance \xC3\x28 text " + "a" * 200)).force_encoding(Encoding::UTF_8)
      expect(dirty.valid_encoding?).to be(false)
      success = instance_double(Process::Status, success?: true)
      allow(Sway::Subprocess).to receive(:capture3).and_return([dirty, "", success])

      result = described_class.new(native_path).call

      expect(result.valid_encoding?).to be(true)
      expect(result).to include("Baltimore ordinance")
      expect { result.present? }.not_to raise_error
    end

    it "scrubs mutool stderr so the ExtractionFailed message is a usable String" do
      native_path = MupdfExtractorSpecHelpers::NATIVE_PDF_PATH
      dirty_err = (+"mutool: cannot open \xC3\x28 document").force_encoding(Encoding::UTF_8)
      failure = instance_double(Process::Status, success?: false, exitstatus: 1)
      allow(Sway::Subprocess).to receive(:capture3).and_return(["", dirty_err, failure])

      # Keep the MESSAGE, not the exception: Steep types a local set to nil
      # as nil, so .message won't type-check. Defaulting to empty string
      # keeps the check meaningful.
      message = begin
        described_class.new(native_path).call
        ""
      rescue MupdfExtractor::ExtractionFailed => e
        e.message
      end

      expect(message.valid_encoding?).to be(true)
      expect(message).to match(/mutool failed.*cannot open/)
    end

    it "scrubs standalone-tesseract stdout on the OCR fallback path" do
      image_path = MupdfExtractorSpecHelpers::IMAGE_PDF_PATH
      described_class.instance_variable_set(:@mutool_ocr_unavailable, true)
      tmpdir = "/tmp/mupdf-ocr-scrub"
      allow(Dir).to receive(:mktmpdir).with("mupdf-ocr-").and_yield(tmpdir)
      allow(Dir).to receive(:[]).with(File.join(tmpdir, "page*.png"))
        .and_return([File.join(tmpdir, "page1.png")])
      success = instance_double(Process::Status, success?: true)
      dirty = (+"OCR'd testimony \xC3\x28 body").force_encoding(Encoding::UTF_8)
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", image_path)
        .and_return(["abc", "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "png", "-r", "300", "-o", File.join(tmpdir, "page%d.png"), image_path)
        .and_return(["", "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("tesseract", File.join(tmpdir, "page1.png"), "stdout", "-l", "eng")
        .and_return([dirty, "", success])

      result = described_class.new(image_path).call

      expect(result.valid_encoding?).to be(true)
      expect(result).to include("OCR'd testimony")
    ensure
      described_class.reset_mutool_ocr_detection!
    end

    # pages.map { run_tesseract } had no page-count limit, and each call
    # gets a 300-second deadline — a 400-page scan is a 33-hour worst case
    # for ONE attachment, with no watchdog above it.
    it "bounds the OCR page count and says so in the text" do
      image_path = MupdfExtractorSpecHelpers::IMAGE_PDF_PATH
      described_class.instance_variable_set(:@mutool_ocr_unavailable, true)
      stub_const("#{described_class}::MAX_OCR_PAGES", 2)
      tmpdir = "/tmp/mupdf-ocr-page-cap"
      rendered = (1..5).map { |page| File.join(tmpdir, "page#{page}.png") }
      allow(Dir).to receive(:mktmpdir).with("mupdf-ocr-").and_yield(tmpdir)
      allow(Dir).to receive(:[]).with(File.join(tmpdir, "page*.png")).and_return(rendered)
      success = instance_double(Process::Status, success?: true)
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", image_path)
        .and_return(["abc", "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "png", "-r", "300", "-o", File.join(tmpdir, "page%d.png"), image_path)
        .and_return(["", "", success])
      rendered.each do |png|
        allow(Sway::Subprocess).to receive(:capture3)
          .with("tesseract", png, "stdout", "-l", "eng")
          .and_return(["text from #{File.basename(png)}", "", success])
      end

      result = described_class.new(image_path).call

      expect(result).to include("page1.png", "page2.png")
      expect(result).not_to include("page3.png")
      expect(result).to include("truncated")
      expect(Sway::Subprocess).not_to have_received(:capture3)
        .with("tesseract", File.join(tmpdir, "page3.png"), "stdout", "-l", "eng")
    ensure
      described_class.reset_mutool_ocr_detection!
    end

    it "scrubs the png-render stderr snippet on the OCR fallback path" do
      image_path = MupdfExtractorSpecHelpers::IMAGE_PDF_PATH
      described_class.instance_variable_set(:@mutool_ocr_unavailable, true)
      tmpdir = "/tmp/mupdf-ocr-scrub-render"
      allow(Dir).to receive(:mktmpdir).with("mupdf-ocr-").and_yield(tmpdir)
      success = instance_double(Process::Status, success?: true)
      dirty_err = (+"render exploded \xC3\x28 badly").force_encoding(Encoding::UTF_8)
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", image_path)
        .and_return(["abc", "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "png", "-r", "300", "-o", File.join(tmpdir, "page%d.png"), image_path)
        .and_return(["", dirty_err, instance_double(Process::Status, success?: false, exitstatus: 1)])

      message = begin
        described_class.new(image_path).call
        ""
      rescue MupdfExtractor::ExtractionFailed => e
        e.message
      end

      expect(message.valid_encoding?).to be(true)
      expect(message).to match(/png render failed.*render exploded/)
    ensure
      described_class.reset_mutool_ocr_detection!
    end
  end

  # When mutool ships without OCR built in, fall back to running tesseract
  # directly — Debian/Alpine mupdf-tools compile with HAVE_TESSERACT=no,
  # spotted by the stderr line OCR Disabled in this build.
  describe "#call — tesseract fallback when mutool OCR is disabled" do
    around do |example|
      with_app_config(:legislation, tessdata_prefix: MupdfExtractorSpecHelpers::TESSDATA_DIR) { example.run }
    end

    before { described_class.reset_mutool_ocr_detection! }
    after { described_class.reset_mutool_ocr_detection! }

    let(:success) { instance_double(Process::Status, success?: true) }
    let(:ocr_disabled_failure) { instance_double(Process::Status, success?: false, exitstatus: 1) }
    let(:image_path) { MupdfExtractorSpecHelpers::IMAGE_PDF_PATH }
    let(:short_native) { "abc" }
    let(:ocr_disabled_stderr) do
      "warning: ICC support is not available\nunsupported error: OCR Disabled in this build\ncannot draw '#{image_path}'\n"
    end

    it "falls back to standalone tesseract when mutool reports 'OCR Disabled in this build'" do
      tmpdir = "/tmp/mupdf-ocr-abcd"
      allow(Dir).to receive(:mktmpdir).with("mupdf-ocr-").and_yield(tmpdir)
      allow(Dir).to receive(:[]).with(File.join(tmpdir, "page*.png"))
        .and_return([File.join(tmpdir, "page1.png"), File.join(tmpdir, "page2.png")])

      stub_mutool("draw", "-F", "txt", image_path, stdout: short_native)
      stub_mutool("draw", "-F", "ocr.txt", "-r", "300", image_path, stderr: ocr_disabled_stderr, success: false, exitstatus: 1)
      stub_mutool("draw", "-F", "png", "-r", "300", "-o", File.join(tmpdir, "page%d.png"), image_path)
      allow(Sway::Subprocess).to receive(:capture3)
        .with("tesseract", File.join(tmpdir, "page1.png"), "stdout", "-l", "eng")
        .and_return(["PAGE ONE TEXT", "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("tesseract", File.join(tmpdir, "page2.png"), "stdout", "-l", "eng")
        .and_return(["PAGE TWO TEXT", "", success])

      result = described_class.new(image_path).call

      expect(result).to eq("PAGE ONE TEXT\n\nPAGE TWO TEXT")
      expect(described_class).to be_mutool_ocr_unavailable
    end

    it "skips the mutool OCR attempt on subsequent calls once 'OCR Disabled' is detected" do
      described_class.instance_variable_set(:@mutool_ocr_unavailable, true)
      tmpdir = "/tmp/mupdf-ocr-efgh"
      allow(Dir).to receive(:mktmpdir).with("mupdf-ocr-").and_yield(tmpdir)
      allow(Dir).to receive(:[]).with(File.join(tmpdir, "page*.png"))
        .and_return([File.join(tmpdir, "page1.png")])

      stub_mutool("draw", "-F", "txt", image_path, stdout: short_native)
      stub_mutool("draw", "-F", "png", "-r", "300", "-o", File.join(tmpdir, "page%d.png"), image_path)
      allow(Sway::Subprocess).to receive(:capture3)
        .with("tesseract", File.join(tmpdir, "page1.png"), "stdout", "-l", "eng")
        .and_return(["ONLY PAGE", "", success])

      described_class.new(image_path).call

      expect(Sway::Subprocess).not_to have_received(:capture3)
        .with("mutool", "draw", "-F", "ocr.txt", "-r", "300", image_path)
    end

    # Detection reads stderr through two size limits (500 chars, 256 KiB),
    # and mutool prints one error line per malformed object — a broken PDF
    # can bury OCR Disabled before either limit is reached.
    it "detects the signature even when it falls outside the 500-char message bound" do
      noisy_stderr = ("warning: object 12 0 R has an invalid /Length\n" * 40) +
        "unsupported error: OCR Disabled in this build\ncannot draw '#{image_path}'\n"
      expect(noisy_stderr.index("OCR Disabled in this build")).to be > 500
      tmpdir = "/tmp/mupdf-ocr-noisy"
      allow(Dir).to receive(:mktmpdir).with("mupdf-ocr-").and_yield(tmpdir)
      allow(Dir).to receive(:[]).with(File.join(tmpdir, "page*.png"))
        .and_return([File.join(tmpdir, "page1.png")])
      stub_mutool("draw", "-F", "txt", image_path, stdout: short_native)
      stub_mutool("draw", "-F", "ocr.txt", "-r", "300", image_path, stderr: noisy_stderr, success: false, exitstatus: 1)
      stub_mutool("draw", "-F", "png", "-r", "300", "-o", File.join(tmpdir, "page%d.png"), image_path)
      allow(Sway::Subprocess).to receive(:capture3)
        .with("tesseract", File.join(tmpdir, "page1.png"), "stdout", "-l", "eng")
        .and_return(["ONLY PAGE", "", success])

      expect(described_class.new(image_path).call).to eq("ONLY PAGE")
      expect(described_class).to be_mutool_ocr_unavailable
    end

    it "detects the signature when the stderr cap trips and the stream is discarded" do
      tmpdir = "/tmp/mupdf-ocr-capped"
      allow(Dir).to receive(:mktmpdir).with("mupdf-ocr-").and_yield(tmpdir)
      allow(Dir).to receive(:[]).with(File.join(tmpdir, "page*.png"))
        .and_return([File.join(tmpdir, "page1.png")])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", image_path)
        .and_return([short_native, "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "ocr.txt", "-r", "300", image_path)
        .and_raise(Sway::Subprocess::OutputTooLarge.new(
          "mutool produced more than 262144 bytes on stderr and was killed",
          stderr: ocr_disabled_stderr
        ))
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "png", "-r", "300", "-o", File.join(tmpdir, "page%d.png"), image_path)
        .and_return(["", "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("tesseract", File.join(tmpdir, "page1.png"), "stdout", "-l", "eng")
        .and_return(["ONLY PAGE", "", success])

      expect(described_class.new(image_path).call).to eq("ONLY PAGE")
      expect(described_class).to be_mutool_ocr_unavailable
    end

    it "re-raises ExtractionFailed when mutool OCR fails for a reason other than 'OCR Disabled'" do
      generic_stderr = "mutool: cannot open document: no such file"
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", image_path)
        .and_return([short_native, "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "ocr.txt", "-r", "300", image_path)
        .and_return(["", generic_stderr, ocr_disabled_failure])

      expect { described_class.new(image_path).call }
        .to raise_error(MupdfExtractor::ExtractionFailed, /cannot open document/)

      expect(described_class).not_to be_mutool_ocr_unavailable
    end

    it "raises ExtractionFailed when the mutool png render step exits non-zero" do
      described_class.instance_variable_set(:@mutool_ocr_unavailable, true)
      tmpdir = "/tmp/mupdf-ocr-render-fail"
      allow(Dir).to receive(:mktmpdir).with("mupdf-ocr-").and_yield(tmpdir)
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", image_path)
        .and_return([short_native, "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "png", "-r", "300", "-o", File.join(tmpdir, "page%d.png"), image_path)
        .and_return(["", "render exploded", instance_double(Process::Status, success?: false, exitstatus: 1)])

      expect { described_class.new(image_path).call }
        .to raise_error(MupdfExtractor::ExtractionFailed, /png render failed.*render exploded/)
    end

    it "raises ExtractionFailed when tesseract exits non-zero on any page" do
      described_class.instance_variable_set(:@mutool_ocr_unavailable, true)
      tmpdir = "/tmp/mupdf-ocr-tess-fail"
      allow(Dir).to receive(:mktmpdir).with("mupdf-ocr-").and_yield(tmpdir)
      allow(Dir).to receive(:[]).with(File.join(tmpdir, "page*.png"))
        .and_return([File.join(tmpdir, "page1.png")])

      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", image_path)
        .and_return([short_native, "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "png", "-r", "300", "-o", File.join(tmpdir, "page%d.png"), image_path)
        .and_return(["", "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("tesseract", File.join(tmpdir, "page1.png"), "stdout", "-l", "eng")
        .and_return(["", "tesseract: language data not found", instance_double(Process::Status, success?: false, exitstatus: 1)])

      expect { described_class.new(image_path).call }
        .to raise_error(MupdfExtractor::ExtractionFailed, /tesseract failed.*language data not found/)
    end

    it "raises ExtractionFailed when the mutool png render floods its output cap" do
      described_class.instance_variable_set(:@mutool_ocr_unavailable, true)
      tmpdir = "/tmp/mupdf-ocr-render-flood"
      allow(Dir).to receive(:mktmpdir).with("mupdf-ocr-").and_yield(tmpdir)
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", image_path)
        .and_return([short_native, "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "png", "-r", "300", "-o", File.join(tmpdir, "page%d.png"), image_path)
        .and_raise(Sway::Subprocess::OutputTooLarge, "mutool produced more than 262144 bytes on stderr and was killed")

      expect { described_class.new(image_path).call }
        .to raise_error(MupdfExtractor::ExtractionFailed, /png render output too large/i)
    end

    it "raises ExtractionFailed when tesseract floods its output cap on any page" do
      described_class.instance_variable_set(:@mutool_ocr_unavailable, true)
      tmpdir = "/tmp/mupdf-ocr-tess-flood"
      allow(Dir).to receive(:mktmpdir).with("mupdf-ocr-").and_yield(tmpdir)
      allow(Dir).to receive(:[]).with(File.join(tmpdir, "page*.png"))
        .and_return([File.join(tmpdir, "page1.png")])

      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", image_path)
        .and_return([short_native, "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "png", "-r", "300", "-o", File.join(tmpdir, "page%d.png"), image_path)
        .and_return(["", "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("tesseract", File.join(tmpdir, "page1.png"), "stdout", "-l", "eng")
        .and_raise(Sway::Subprocess::OutputTooLarge, "tesseract produced more than 16777216 bytes on stdout and was killed")

      expect { described_class.new(image_path).call }
        .to raise_error(MupdfExtractor::ExtractionFailed, /tesseract output too large/i)
    end

    # The same conversion for the other two subprocess calls, plus
    # Dir.mktmpdir: a machine missing tesseract likely lacks the package
    # entirely, so Errno::ENOENT is the LIKELY case, not exotic.
    it "raises ExtractionFailed, not Errno::ENOENT, when the tesseract binary is absent" do
      described_class.instance_variable_set(:@mutool_ocr_unavailable, true)
      tmpdir = "/tmp/mupdf-ocr-tess-absent"
      allow(Dir).to receive(:mktmpdir).with("mupdf-ocr-").and_yield(tmpdir)
      allow(Dir).to receive(:[]).with(File.join(tmpdir, "page*.png"))
        .and_return([File.join(tmpdir, "page1.png")])

      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", image_path)
        .and_return([short_native, "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "png", "-r", "300", "-o", File.join(tmpdir, "page%d.png"), image_path)
        .and_return(["", "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("tesseract", File.join(tmpdir, "page1.png"), "stdout", "-l", "eng")
        .and_raise(Errno::ENOENT)

      expect { described_class.new(image_path).call }
        .to raise_error(MupdfExtractor::ExtractionFailed, /tesseract unavailable.*ENOENT/)
    end

    it "raises ExtractionFailed, not Errno::ENOENT, when the mutool png render binary is absent" do
      described_class.instance_variable_set(:@mutool_ocr_unavailable, true)
      tmpdir = "/tmp/mupdf-ocr-render-absent"
      allow(Dir).to receive(:mktmpdir).with("mupdf-ocr-").and_yield(tmpdir)

      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", image_path)
        .and_return([short_native, "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "png", "-r", "300", "-o", File.join(tmpdir, "page%d.png"), image_path)
        .and_raise(Errno::ENOENT)

      expect { described_class.new(image_path).call }
        .to raise_error(MupdfExtractor::ExtractionFailed, /png render unavailable.*ENOENT/)
    end

    # A full or read-only /tmp is a real risk on the Pi, and Dir.mktmpdir's own
    # SystemCallError was unguarded too.
    it "raises ExtractionFailed, not Errno::ENOSPC, when the OCR workspace cannot be created" do
      described_class.instance_variable_set(:@mutool_ocr_unavailable, true)
      allow(Dir).to receive(:mktmpdir).with("mupdf-ocr-").and_raise(Errno::ENOSPC)

      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", image_path)
        .and_return([short_native, "", success])

      expect { described_class.new(image_path).call }
        .to raise_error(MupdfExtractor::ExtractionFailed, /ocr workspace unavailable.*ENOSPC/i)
    end

    it "raises ExtractionFailed when the mutool png render produces zero pages" do
      described_class.instance_variable_set(:@mutool_ocr_unavailable, true)
      tmpdir = "/tmp/mupdf-ocr-empty"
      allow(Dir).to receive(:mktmpdir).with("mupdf-ocr-").and_yield(tmpdir)
      allow(Dir).to receive(:[]).with(File.join(tmpdir, "page*.png")).and_return(
        [] #: Array[untyped]
      )

      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", image_path)
        .and_return([short_native, "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "png", "-r", "300", "-o", File.join(tmpdir, "page%d.png"), image_path)
        .and_return(["", "", success])

      expect { described_class.new(image_path).call }
        .to raise_error(MupdfExtractor::ExtractionFailed, /produced no pages/)
    end
  end

  # mutool's OCR mode exits 0 with EMPTY stdout on unusable language data,
  # invisible to preflight! — so #call returned an empty success, hiding
  # the failure next to a green stage.
  describe "#call — a silently-empty OCR result (A2-WR-03)" do
    around do |example|
      with_app_config(:legislation, tessdata_prefix: MupdfExtractorSpecHelpers::TESSDATA_DIR) { example.run }
    end

    before { described_class.reset_mutool_ocr_detection! }
    after { described_class.reset_mutool_ocr_detection! }

    let(:success) { instance_double(Process::Status, success?: true) }
    let(:image_path) { MupdfExtractorSpecHelpers::IMAGE_PDF_PATH }
    let(:short_native) { "abc" }

    it "raises rather than returning '' when mutool OCR exits 0 with no output" do
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", image_path)
        .and_return([short_native, "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "ocr.txt", "-r", "300", image_path)
        .and_return(["", "", success])

      expect { described_class.new(image_path).call }
        .to raise_error(MupdfExtractor::ExtractionFailed, /ocr produced no text/i)
    end

    it "raises when mutool OCR returns whitespace only" do
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", image_path)
        .and_return([short_native, "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "ocr.txt", "-r", "300", image_path)
        .and_return(["   \n\n \t ", "", success])

      expect { described_class.new(image_path).call }
        .to raise_error(MupdfExtractor::ExtractionFailed, /ocr produced no text/i)
    end

    it "names the PDF so the per-bill failure reason is actionable" do
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", image_path)
        .and_return([short_native, "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "ocr.txt", "-r", "300", image_path)
        .and_return(["", "", success])

      message = begin
        described_class.new(image_path).call
        ""
      rescue MupdfExtractor::ExtractionFailed => e
        e.message
      end

      expect(message).to include(File.basename(image_path))
    end

    it "raises when standalone tesseract recognises nothing on any page" do
      described_class.instance_variable_set(:@mutool_ocr_unavailable, true)
      tmpdir = "/tmp/mupdf-ocr-blank"
      pages = [File.join(tmpdir, "page1.png"), File.join(tmpdir, "page2.png")]
      allow(Dir).to receive(:mktmpdir).with("mupdf-ocr-").and_yield(tmpdir)
      allow(Dir).to receive(:[]).with(File.join(tmpdir, "page*.png")).and_return(pages)
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", image_path)
        .and_return([short_native, "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "png", "-r", "300", "-o", File.join(tmpdir, "page%d.png"), image_path)
        .and_return(["", "", success])
      pages.each do |png|
        allow(Sway::Subprocess).to receive(:capture3)
          .with("tesseract", png, "stdout", "-l", "eng")
          .and_return(["", "", success])
      end

      expect { described_class.new(image_path).call }
        .to raise_error(MupdfExtractor::ExtractionFailed, /ocr produced no text/i)
    end

    # The page cap appends OCR_PAGE_TRUNCATION_NOTICE, which is not blank —
    # a check after that append would read the notice as recovered text,
    # so emptiness has to be checked BEFORE appending it.
    it "raises on a blank OCR result even when the page cap would append its truncation notice" do
      described_class.instance_variable_set(:@mutool_ocr_unavailable, true)
      stub_const("#{described_class}::MAX_OCR_PAGES", 2)
      tmpdir = "/tmp/mupdf-ocr-blank-truncated"
      rendered = (1..5).map { |page| File.join(tmpdir, "page#{page}.png") }
      allow(Dir).to receive(:mktmpdir).with("mupdf-ocr-").and_yield(tmpdir)
      allow(Dir).to receive(:[]).with(File.join(tmpdir, "page*.png")).and_return(rendered)
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "txt", image_path)
        .and_return([short_native, "", success])
      allow(Sway::Subprocess).to receive(:capture3)
        .with("mutool", "draw", "-F", "png", "-r", "300", "-o", File.join(tmpdir, "page%d.png"), image_path)
        .and_return(["", "", success])
      rendered.each do |png|
        allow(Sway::Subprocess).to receive(:capture3)
          .with("tesseract", png, "stdout", "-l", "eng")
          .and_return(["", "", success])
      end

      expect { described_class.new(image_path).call }
        .to raise_error(MupdfExtractor::ExtractionFailed, /ocr produced no text/i)
    end
  end

  describe "#call — remote extractor via pdf_extractor_url" do
    around do |example|
      with_app_config(:legislation, tessdata_prefix: MupdfExtractorSpecHelpers::TESSDATA_DIR) { example.run }
    end

    remote_url = "http://pdf-extractor:8085"
    extract_endpoint = "#{remote_url}/extract"
    native_path = MupdfExtractorSpecHelpers::NATIVE_PDF_PATH

    it "uses the local subprocess path when pdf_extractor_url is nil" do
      with_app_config(:legislation, pdf_extractor_url: nil) do
        success = instance_double(Process::Status, success?: true)
        allow(Sway::Subprocess).to receive(:capture3)
          .with("mutool", "draw", "-F", "txt", native_path)
          .and_return(["local extracted text " * 10, "", success])

        result = described_class.new(native_path).call

        expect(result).to include("local extracted text")
        expect(Sway::Subprocess).to have_received(:capture3).with("mutool", "draw", "-F", "txt", native_path)
      end
    end

    it "posts JSON to /extract with parameters and returns extracted text when pdf_extractor_url is set" do
      with_app_config(:legislation, pdf_extractor_url: remote_url) do
        stub_request(:post, extract_endpoint)
          .with(
            body: {
              pdf_path: native_path,
              min_native_chars: described_class::MIN_NATIVE_CHARS,
              ocr_dpi: described_class::OCR_DPI,
              max_ocr_pages: described_class::MAX_OCR_PAGES
            }.to_json,
            headers: {"Content-Type" => "application/json"}
          )
          .to_return(
            status: 200,
            headers: {"Content-Type" => "application/json"},
            body: {text: "remote text content", ocr_used: false, truncated: false}.to_json
          )

        result = described_class.new(native_path).call
        expect(result).to eq("remote text content")
      end
    end

    it "preserves path prefixes and handles trailing slashes when building the extract URI" do
      subpath_url = "http://service.local/subpath"
      with_app_config(:legislation, pdf_extractor_url: "#{subpath_url}/") do
        stub_request(:post, "http://service.local/subpath/extract")
          .to_return(
            status: 200,
            headers: {"Content-Type" => "application/json"},
            body: {text: "subpath text content", ocr_used: false, truncated: false}.to_json
          )

        result = described_class.new(native_path).call
        expect(result).to eq("subpath text content")
      end
    end

    it "appends OCR_PAGE_TRUNCATION_NOTICE when truncated is true in the remote response" do
      with_app_config(:legislation, pdf_extractor_url: remote_url) do
        stub_request(:post, extract_endpoint)
          .to_return(
            status: 200,
            headers: {"Content-Type" => "application/json"},
            body: {text: "partial text", ocr_used: true, truncated: true}.to_json
          )

        result = described_class.new(native_path).call
        expect(result).to eq("partial text#{described_class::OCR_PAGE_TRUNCATION_NOTICE}")
      end
    end

    it "raises ExtractionFailed with a scrubbed message when remote extractor returns non-200 status" do
      with_app_config(:legislation, pdf_extractor_url: remote_url) do
        stub_request(:post, extract_endpoint)
          .to_return(
            status: 500,
            body: "internal worker error"
          )

        expect { described_class.new(native_path).call }
          .to raise_error(MupdfExtractor::ExtractionFailed, /500/)
      end
    end

    it "raises ExtractionFailed when remote extractor returns empty or whitespace-only text" do
      with_app_config(:legislation, pdf_extractor_url: remote_url) do
        stub_request(:post, extract_endpoint)
          .to_return(
            status: 200,
            headers: {"Content-Type" => "application/json"},
            body: {text: "   \n\t  ", ocr_used: false, truncated: false}.to_json
          )

        expect { described_class.new(native_path).call }
          .to raise_error(MupdfExtractor::ExtractionFailed, /empty text/i)
      end
    end

    it "raises ExtractionFailed with a scrubbed message when a network error occurs" do
      with_app_config(:legislation, pdf_extractor_url: remote_url) do
        stub_request(:post, extract_endpoint).to_raise(Errno::ECONNREFUSED.new("Connection refused"))

        expect { described_class.new(native_path).call }
          .to raise_error(MupdfExtractor::ExtractionFailed, /ECONNREFUSED/i)
      end
    end

    it "raises ExtractionFailed with a scrubbed message when a timeout occurs" do
      with_app_config(:legislation, pdf_extractor_url: remote_url) do
        stub_request(:post, extract_endpoint).to_timeout

        expect { described_class.new(native_path).call }
          .to raise_error(MupdfExtractor::ExtractionFailed, /timed? out/i)
      end
    end

    it "scrubs invalid UTF-8 and caps the message to 500 characters on failure" do
      with_app_config(:legislation, pdf_extractor_url: remote_url) do
        dirty_err = (+"remote exploded \xC3\x28 badly " + "x" * 600).force_encoding(Encoding::UTF_8)
        stub_request(:post, extract_endpoint)
          .to_return(
            status: 502,
            body: dirty_err
          )

        message = begin
          described_class.new(native_path).call
          ""
        rescue MupdfExtractor::ExtractionFailed => e
          e.message
        end

        expect(message.valid_encoding?).to be(true)
        expect(message.length).to be <= 500
        expect(message).to match(/502/)
      end
    end

    it "extracts remotely without local tessdata when pdf_extractor_url is set and tessdata_prefix is nil" do
      with_app_config(:legislation, tessdata_prefix: nil, pdf_extractor_url: remote_url) do
        stub_request(:post, extract_endpoint)
          .to_return(
            status: 200,
            headers: {"Content-Type" => "application/json"},
            body: {text: "remote text without local tessdata", ocr_used: true, truncated: false}.to_json
          )

        result = described_class.new(native_path).call
        expect(result).to eq("remote text without local tessdata")
      end
    end
  end
end
