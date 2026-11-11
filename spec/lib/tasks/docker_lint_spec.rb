# frozen_string_literal: true

require "rails_helper"

# @lat: [[docker-lint-rake-tasks-design#docker:lint:tessdata_parity]]
require "rake"
Rails.application.load_tasks unless Rake::Task.task_defined?("docker:lint:tessdata_parity")
DockerLintSpecHelpers = DockerLintHelpers unless defined?(DockerLintSpecHelpers)

RSpec.describe "docker:lint:tessdata_parity" do
  describe "extract_tesseract_langs — Debian package prefix" do
    let(:prefix) { "tesseract-ocr-" }

    it "extracts a single language from a basic install line" do
      body = "RUN apt-get install -y tesseract-ocr-eng"
      result = DockerLintSpecHelpers.extract_tesseract_langs(
        body, package_prefix: prefix, skip_bare_base: true
      )
      expect(result.to_a).to eq(["eng"])
    end

    it "extracts multiple languages from a single multi-package line" do
      body = "RUN apt-get install -y tesseract-ocr-eng tesseract-ocr-fra"
      result = DockerLintSpecHelpers.extract_tesseract_langs(
        body, package_prefix: prefix, skip_bare_base: true
      )
      expect(result.to_a.sort).to eq(%w[eng fra])
    end

    it "extracts languages across line-continuation form (\\-wrapped apt-get)" do
      body = <<~DOCKERFILE
        RUN apt-get install -y \\
            tesseract-ocr \\
            tesseract-ocr-eng \\
            tesseract-ocr-fra && \\
            apt-get clean
      DOCKERFILE
      result = DockerLintSpecHelpers.extract_tesseract_langs(
        body, package_prefix: prefix, skip_bare_base: true
      )
      expect(result.to_a.sort).to eq(%w[eng fra])
    end

    it "does NOT spuriously match the unprefixed `tesseract-ocr` base package" do
      body = "RUN apt-get install -y tesseract-ocr tesseract-ocr-eng"
      result = DockerLintSpecHelpers.extract_tesseract_langs(
        body, package_prefix: prefix, skip_bare_base: true
      )
      # The bare base package names no language; only tesseract-ocr-eng counts.
      expect(result.to_a).to eq(["eng"])
    end

    it "skips language tokens that appear inside comment lines (cycle-15 LOW-15-3)" do
      # What is installed is what counts. Comment lines (`\A\s*#`) are removed
      # before scanning, so an out-of-date comment in one dockerfile cannot hide
      # a real difference in the other.
      body = "# tesseract-ocr-eng deprecated as of 2026"
      result = DockerLintSpecHelpers.extract_tesseract_langs(
        body, package_prefix: prefix, skip_bare_base: true
      )
      expect(result.to_a).to be_empty
    end

    it "still captures active-line installs when other lines are commented" do
      # Make sure the comment filter does not reach too far and drop the real
      # install line sitting next to a comment.
      body = <<~DOCKERFILE
        # historic note: tesseract-ocr-deu used to ship here
        RUN apt-get install -y tesseract-ocr-eng tesseract-ocr-fra
      DOCKERFILE
      result = DockerLintSpecHelpers.extract_tesseract_langs(
        body, package_prefix: prefix, skip_bare_base: true
      )
      expect(result.to_a.sort).to eq(%w[eng fra])
    end
  end

  describe "extract_tesseract_langs — Alpine package prefix" do
    let(:prefix) { "tesseract-ocr-data-" }

    it "extracts a single language from a basic Alpine install line" do
      body = "RUN apk add --no-cache tesseract-ocr tesseract-ocr-data-eng"
      result = DockerLintSpecHelpers.extract_tesseract_langs(
        body, package_prefix: prefix
      )
      expect(result.to_a).to eq(["eng"])
    end

    it "extracts multiple languages from an Alpine multi-package line" do
      body = "RUN apk add --no-cache tesseract-ocr-data-eng tesseract-ocr-data-fra"
      result = DockerLintSpecHelpers.extract_tesseract_langs(
        body, package_prefix: prefix
      )
      expect(result.to_a.sort).to eq(%w[eng fra])
    end

    it "does NOT match the Debian-style `tesseract-ocr-eng` token when looking for the Alpine prefix" do
      body = "RUN apt-get install -y tesseract-ocr-eng"
      result = DockerLintSpecHelpers.extract_tesseract_langs(
        body, package_prefix: prefix
      )
      # This line is Debian style, so there is nothing with the Alpine prefix to find.
      expect(result.to_a).to be_empty
    end
  end

  describe "negative cases — false-positive guards" do
    let(:prefix) { "tesseract-ocr-" }

    it "does NOT match unrelated tokens that happen to contain `tesseract`" do
      body = "RUN echo 'libtesseract5 already present'"
      result = DockerLintSpecHelpers.extract_tesseract_langs(
        body, package_prefix: prefix, skip_bare_base: true
      )
      expect(result.to_a).to be_empty
    end

    it "requires at least 3 alpha characters for the language suffix (rejects single-letter typos)" do
      body = "RUN apt-get install -y tesseract-ocr-en"
      result = DockerLintSpecHelpers.extract_tesseract_langs(
        body, package_prefix: prefix, skip_bare_base: true
      )
      # Two-letter codes are rejected on purpose: the pattern demands three or
      # more letters, because Tesseract's language data files use the
      # three-letter ISO 639-2/3 codes.
      expect(result.to_a).to be_empty
    end
  end

  describe "cross-dockerfile parity (integration)" do
    # A fixed pair of fake install lines, so this spec does not depend on what
    # the real dockerfiles contain right now.
    let(:debian_body) { "RUN apt-get install -y tesseract-ocr tesseract-ocr-eng" }
    let(:alpine_body) { "RUN apk add --no-cache tesseract-ocr tesseract-ocr-data-eng" }

    it "matches across the two prefix families when language sets align" do
      debian = DockerLintSpecHelpers.extract_tesseract_langs(
        debian_body, package_prefix: "tesseract-ocr-", skip_bare_base: true
      )
      alpine = DockerLintSpecHelpers.extract_tesseract_langs(
        alpine_body, package_prefix: "tesseract-ocr-data-"
      )
      expect((debian - alpine).to_a).to be_empty
      expect((alpine - debian).to_a).to be_empty
    end

    it "detects drift when a language is added to one dockerfile but not the other" do
      drifted_debian = "#{debian_body} tesseract-ocr-fra"
      debian = DockerLintSpecHelpers.extract_tesseract_langs(
        drifted_debian, package_prefix: "tesseract-ocr-", skip_bare_base: true
      )
      alpine = DockerLintSpecHelpers.extract_tesseract_langs(
        alpine_body, package_prefix: "tesseract-ocr-data-"
      )
      expect((debian - alpine).to_a).to eq(["fra"])
    end
  end

  describe "shipped dockerfiles (smoke test)" do
    it "reports the same language set across .dockerdev/Dockerfile and ops/pdf-extractor/Dockerfile" do
      debian_body = Rails.root.join(".dockerdev", "Dockerfile").read
      alpine_body = Rails.root.join("ops", "pdf-extractor", "Dockerfile").read
      debian = DockerLintSpecHelpers.extract_tesseract_langs(
        debian_body, package_prefix: "tesseract-ocr-", skip_bare_base: true
      )
      alpine = DockerLintSpecHelpers.extract_tesseract_langs(
        alpine_body, package_prefix: "tesseract-ocr-data-"
      )
      expect((debian - alpine).to_a.sort).to eq([]),
        "Debian-only languages: #{(debian - alpine).to_a.inspect}"
      expect((alpine - debian).to_a.sort).to eq([]),
        "Alpine-only languages: #{(alpine - debian).to_a.inspect}"
    end

    it "keeps mupdf-tools, tesseract-ocr, and TESSDATA_PREFIX out of production.alpine.dockerfile" do
      production_body = Rails.root.join("docker", "dockerfiles", "production.alpine.dockerfile").read
      active_text = production_body.each_line.reject { |line| line =~ /\A\s*#/ }.join

      expect(active_text).not_to match(/\bmupdf-tools\b/)
      expect(active_text).not_to match(/\btesseract-ocr/)
      expect(active_text).not_to match(/\bTESSDATA_PREFIX\b/)
    end
  end
end

# @lat: [[docker-lint-rake-tasks-design#docker:lint:sqlite_flags]]
RSpec.describe "docker:lint:sqlite_flags" do
  describe "extract_sqlite_options" do
    it "extracts a single option from a bundle config line" do
      body = %(RUN bundle config set build.sqlite3 "--with-sqlite-cflags='-DSQLITE_DQS=0'")
      expect(DockerLintSpecHelpers.extract_sqlite_options(body).to_a).to eq(["SQLITE_DQS=0"])
    end

    it "keeps the value attached so a changed value is a different option" do
      body = "-DSQLITE_DEFAULT_PAGE_SIZE=8192"
      expect(DockerLintSpecHelpers.extract_sqlite_options(body).to_a)
        .to eq(["SQLITE_DEFAULT_PAGE_SIZE=8192"])
    end

    it "extracts a valueless option" do
      body = "-DSQLITE_USE_ALLOCA"
      expect(DockerLintSpecHelpers.extract_sqlite_options(body).to_a).to eq(["SQLITE_USE_ALLOCA"])
    end

    it "extracts every option from a full flag string" do
      body = %(RUN bundle config set build.sqlite3 ) +
        %("--with-sqlite-cflags='-DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_DQS=0 -DSQLITE_USE_ALLOCA'")
      expect(DockerLintSpecHelpers.extract_sqlite_options(body).to_a.sort)
        .to eq(%w[SQLITE_DEFAULT_MEMSTATUS=0 SQLITE_DQS=0 SQLITE_USE_ALLOCA])
    end

    it "skips comment lines, so prose naming a forbidden option is not a violation" do
      body = <<~DOCKERFILE
        # SQLITE_OMIT_PROGRESS_CALLBACK is deliberately absent: -DSQLITE_OMIT_PROGRESS_CALLBACK
        # would remove a symbol the gem calls.
        RUN bundle config set build.sqlite3 "--with-sqlite-cflags='-DSQLITE_DQS=0'"
      DOCKERFILE
      expect(DockerLintSpecHelpers.extract_sqlite_options(body).to_a).to eq(["SQLITE_DQS=0"])
    end

    it "ignores non-SQLITE defines" do
      body = "-DNDEBUG -DSQLITE_DQS=0 -DHAVE_USLEEP"
      expect(DockerLintSpecHelpers.extract_sqlite_options(body).to_a).to eq(["SQLITE_DQS=0"])
    end
  end

  describe "forbidden_sqlite_options_in" do
    it "passes an option set that holds neither forbidden option" do
      options = Set.new(%w[SQLITE_DQS=0 SQLITE_USE_ALLOCA SQLITE_OMIT_SHARED_CACHE])
      expect(DockerLintSpecHelpers.forbidden_sqlite_options_in(options)).to be_empty
    end

    it "catches SQLITE_OMIT_PROGRESS_CALLBACK, which builds fine and kills the Alpine image at boot" do
      options = Set.new(%w[SQLITE_DQS=0 SQLITE_OMIT_PROGRESS_CALLBACK])
      found = DockerLintSpecHelpers.forbidden_sqlite_options_in(options)
      expect(found.keys).to eq(["SQLITE_OMIT_PROGRESS_CALLBACK"])
      expect(found.values.first).to include("sqlite3_progress_handler")
    end

    it "catches SQLITE_DEFAULT_PAGE_SIZE whatever value it carries" do
      %w[16384 8192 32768].each do |size|
        options = Set.new(["SQLITE_DEFAULT_PAGE_SIZE=#{size}"])
        found = DockerLintSpecHelpers.forbidden_sqlite_options_in(options)
        expect(found.keys).to eq(["SQLITE_DEFAULT_PAGE_SIZE"]),
          "page size #{size} slipped past the gate"
        expect(found.values.first).to include("Litestream")
      end
    end

    it "catches a bare SQLITE_DEFAULT_PAGE_SIZE with no value" do
      found = DockerLintSpecHelpers.forbidden_sqlite_options_in(Set.new(["SQLITE_DEFAULT_PAGE_SIZE"]))
      expect(found.keys).to eq(["SQLITE_DEFAULT_PAGE_SIZE"])
    end

    it "reports both forbidden options when both are present" do
      options = Set.new(%w[SQLITE_OMIT_PROGRESS_CALLBACK SQLITE_DEFAULT_PAGE_SIZE=16384])
      expect(DockerLintSpecHelpers.forbidden_sqlite_options_in(options).keys.sort)
        .to eq(%w[SQLITE_DEFAULT_PAGE_SIZE SQLITE_OMIT_PROGRESS_CALLBACK])
    end
  end

  describe "shipped dockerfiles" do
    # Every dockerfile in the repo, the same set the rake task scans. Reading
    # them off disk rather than naming a pair means a new dockerfile is covered
    # the day it lands, and a rename shows up as a missing file rather than as
    # a gate that quietly checks nothing.
    let(:shipped) do
      paths = (
        Rails.root.glob("docker/dockerfiles/*.dockerfile") +
          Rails.root.glob(".dockerdev/Dockerfile")
      ).sort
      paths.to_h do |path|
        [path.relative_path_from(Rails.root).to_s,
          DockerLintSpecHelpers.extract_sqlite_options(path.read)]
      end
    end
    let(:declaring) { shipped.reject { |_, set| set.empty? } }
    let(:alpine) { shipped.fetch("docker/dockerfiles/production.alpine.dockerfile") }

    it "finds both dockerfiles that build an image" do
      expect(shipped.keys).to include(
        "docker/dockerfiles/production.alpine.dockerfile",
        ".dockerdev/Dockerfile"
      )
    end

    # @lat: [[docker-lint-rake-tasks-design#docker:lint:sqlite_flags]]
    it "has no dockerfile that builds nothing" do
      expect(shipped.keys).not_to include("docker/dockerfiles/local.dockerfile")
    end

    it "compiles the same SQLite options in every dockerfile that sets any" do
      expect(declaring.values.uniq.size).to eq(1),
        "option sets diverge: #{declaring.transform_values { |set| set.to_a.sort }.inspect}"
    end

    it "covers the dev image dip actually runs, not only the reference file" do
      expect(declaring.keys).to include(".dockerdev/Dockerfile")
    end

    it "sets options at all, so an empty match cannot pass for a match" do
      expect(alpine).not_to be_empty
    end

    it "ships no forbidden option in any dockerfile" do
      shipped.each do |file, set|
        expect(DockerLintSpecHelpers.forbidden_sqlite_options_in(set)).to be_empty,
          "#{file} carries a forbidden option"
      end
    end

    it "compiles the options production actually needs" do
      expect(alpine.to_a.sort).to eq(%w[
        SQLITE_DEFAULT_MEMSTATUS=0
        SQLITE_DQS=0
        SQLITE_ENABLE_FTS5
        SQLITE_LIKE_DOESNT_MATCH_BLOBS
        SQLITE_MAX_EXPR_DEPTH=0
        SQLITE_OMIT_SHARED_CACHE
        SQLITE_USE_ALLOCA
      ])
    end
  end
end

# @lat: [[docker-lint-rake-tasks-design#docker:lint:sqlite_runtime]]
RSpec.describe "docker:lint:sqlite_runtime" do
  # What the deployed container reports, trimmed to the entries these checks
  # read. Copied from a live `PRAGMA compile_options` on the production
  # machine, 2026-08-04.
  def production_reported
    Set.new(%w[
      DEFAULT_MEMSTATUS=0
      DEFAULT_PAGE_SIZE=4096
      DQS=0
      ENABLE_FTS5
      LIKE_DOESNT_MATCH_BLOBS
      MAX_EXPR_DEPTH=0
      OMIT_SHARED_CACHE
      USE_ALLOCA
    ])
  end

  def shipped_declared
    DockerLintSpecHelpers.extract_sqlite_options(
      Rails.root.join("docker", "dockerfiles", "production.alpine.dockerfile").read
    )
  end

  describe "sqlite_options_as_reported" do
    it "drops the SQLITE_ prefix, which the PRAGMA does not print" do
      declared = Set.new(%w[SQLITE_DQS=0 SQLITE_USE_ALLOCA])
      expect(DockerLintSpecHelpers.sqlite_options_as_reported(declared).to_a.sort)
        .to eq(%w[DQS=0 USE_ALLOCA])
    end

    it "keeps the value attached, so a changed value is still a difference" do
      declared = Set.new(%w[SQLITE_MAX_EXPR_DEPTH=0])
      expect(DockerLintSpecHelpers.sqlite_options_as_reported(declared).to_a)
        .to eq(%w[MAX_EXPR_DEPTH=0])
    end
  end

  describe "sqlite_runtime_problems" do
    it "passes the exact pair the production machine reports" do
      expect(
        DockerLintSpecHelpers.sqlite_runtime_problems(
          declared: shipped_declared, reported: production_reported
        )
      ).to be_empty
    end

    it "names every option the build left out" do
      short = production_reported - %w[DQS=0 USE_ALLOCA]
      problems = DockerLintSpecHelpers.sqlite_runtime_problems(
        declared: shipped_declared, reported: short
      )
      expect(problems.size).to eq(1)
      expect(problems.first).to include("DQS=0", "USE_ALLOCA")
    end

    it "treats a changed value as missing rather than as present" do
      wrong = (production_reported - ["MAX_EXPR_DEPTH=0"]) << "MAX_EXPR_DEPTH=1000"
      problems = DockerLintSpecHelpers.sqlite_runtime_problems(
        declared: shipped_declared, reported: wrong
      )
      expect(problems.first).to include("MAX_EXPR_DEPTH=0")
    end

    # A stale gitignored .bundle/config can leave every declared option present
    # plus the two the project refuses, because the gem was compiled from it and
    # nothing rebuilt it. A check that only looked for missing options would
    # pass that state.
    it "catches the CI runner's actual state, where nothing was missing" do
      stale = (production_reported - ["DEFAULT_PAGE_SIZE=4096"]) +
        %w[DEFAULT_PAGE_SIZE=16384 OMIT_PROGRESS_CALLBACK]

      problems = DockerLintSpecHelpers.sqlite_runtime_problems(
        declared: shipped_declared, reported: stale
      )

      expect(problems.size).to eq(2)
      expect(problems.join("\n")).to include("OMIT_PROGRESS_CALLBACK", "sqlite3_progress_handler")
      expect(problems.join("\n")).to include("DEFAULT_PAGE_SIZE=16384", "Litestream")
    end

    it "accepts SQLite's own page size, which every build reports either way" do
      expect(production_reported).to include("DEFAULT_PAGE_SIZE=4096")
      expect(
        DockerLintSpecHelpers.sqlite_runtime_problems(
          declared: shipped_declared, reported: production_reported
        )
      ).to be_empty
    end

    it "reads the page size by value, since absence would prove nothing" do
      %w[8192 16384 32768].each do |size|
        reported = (production_reported - ["DEFAULT_PAGE_SIZE=4096"]) << "DEFAULT_PAGE_SIZE=#{size}"
        problems = DockerLintSpecHelpers.sqlite_runtime_problems(
          declared: shipped_declared, reported: reported
        )
        expect(problems.join).to include("DEFAULT_PAGE_SIZE=#{size}"),
          "page size #{size} slipped past the gate"
      end
    end

    it "reports nothing at all when a build is clean, so the gate can stay quiet" do
      expect(
        DockerLintSpecHelpers.sqlite_runtime_problems(
          declared: Set.new(%w[SQLITE_DQS=0]), reported: Set.new(%w[DQS=0 DEFAULT_PAGE_SIZE=4096])
        )
      ).to eq([])
    end
  end

  describe "the shipped dockerfile" do
    it "declares options that all map onto reported names" do
      expect(DockerLintSpecHelpers.sqlite_options_as_reported(shipped_declared).to_a.sort)
        .to eq(%w[
          DEFAULT_MEMSTATUS=0
          DQS=0
          ENABLE_FTS5
          LIKE_DOESNT_MATCH_BLOBS
          MAX_EXPR_DEPTH=0
          OMIT_SHARED_CACHE
          USE_ALLOCA
        ])
    end

    # The workflow reads the option string out of this file with sed rather than
    # repeating it, so the line has to stay findable. A rename or a reflow that
    # splits it would leave CI compiling a default SQLite and saying nothing.
    it "keeps the cflags argument on one line, where the workflow's sed finds it" do
      body = Rails.root.join("docker", "dockerfiles", "production.alpine.dockerfile").read
      matched = body[/--with-sqlite-cflags='[^']*'/]
      expect(matched).not_to be_nil,
        "the workflow step 'Compile SQLite with the same options as the images' greps for this"
      expect(matched).to include("-DSQLITE_DQS=0")
    end
  end
end
