# frozen_string_literal: true

# @lat: [[toolchain-pins#Toolchain pins#Why the dockerfile gates read every file and then read the running library]]
module DockerLintHelpers
  module_function

  def extract_tesseract_langs(body, package_prefix:, skip_bare_base: false)
    active_lines = body.each_line.reject { |line| line =~ /\A\s*#/ }
    scan_target = active_lines.join
    langs = scan_target.scan(/\b#{Regexp.escape(package_prefix)}([a-z]{3,})\b/).flatten.to_set
    langs.delete("data") if skip_bare_base
    langs.delete("ocr") if skip_bare_base
    langs
  end

  FORBIDDEN_SQLITE_OPTIONS = {
    "SQLITE_OMIT_PROGRESS_CALLBACK" =>
      "removes sqlite3_progress_handler, which the sqlite3 gem's C extension " \
      "calls. The build succeeds and the Alpine image then dies at boot with " \
      "`Error relocating ...sqlite3_native.so: sqlite3_progress_handler: " \
      "symbol not found`. Debian hides it because glibc binds lazily.",
    "SQLITE_DEFAULT_PAGE_SIZE" =>
      "is the only option here that changes bytes on disk. Page size is fixed " \
      "when a database is created, so it cannot help the existing production " \
      "database, and it would make a rebuilt one differ from the database " \
      "Litestream replicates. Change page size deliberately with PRAGMA " \
      "page_size + VACUUM, never as a side effect of a build flag."
  }.freeze

  def extract_sqlite_options(body)
    active_lines = body.each_line.reject { |line| line =~ /\A\s*#/ }
    active_lines.join.scan(/-D(SQLITE_[A-Z0-9_]+(?:=[A-Za-z0-9_]+)?)/).flatten.to_set
  end

  def forbidden_sqlite_options_in(options)
    names = options.map { |option| option.split("=").first }.to_set
    FORBIDDEN_SQLITE_OPTIONS.slice(*names)
  end

  SQLITE_UNSET_DEFAULT_PAGE_SIZE = "4096"

  def sqlite_options_as_reported(options)
    options.map { |option| option.delete_prefix("SQLITE_") }.to_set
  end

  def sqlite_runtime_problems(declared:, reported:)
    problems = []

    missing = (sqlite_options_as_reported(declared) - reported).to_a.sort
    unless missing.empty?
      problems << "does not have #{missing.inspect}, which the dockerfiles compile."
    end

    if reported.include?("OMIT_PROGRESS_CALLBACK")
      problems << "was built with -DSQLITE_OMIT_PROGRESS_CALLBACK, which " \
        "#{FORBIDDEN_SQLITE_OPTIONS.fetch("SQLITE_OMIT_PROGRESS_CALLBACK")}"
    end

    page_size = reported.find { |option| option.start_with?("DEFAULT_PAGE_SIZE=") }
    if page_size && page_size != "DEFAULT_PAGE_SIZE=#{SQLITE_UNSET_DEFAULT_PAGE_SIZE}"
      problems << "reports #{page_size}, so a build set -DSQLITE_DEFAULT_PAGE_SIZE. That " \
        "#{FORBIDDEN_SQLITE_OPTIONS.fetch("SQLITE_DEFAULT_PAGE_SIZE")}"
    end

    problems
  end
end

namespace :docker do
  namespace :lint do
    # @lat: [[toolchain-pins#Toolchain pins#Why the dockerfile gates read every file and then read the running library]]
    desc "Check that the dockerfiles install the same tesseract language packages"
    task :tessdata_parity do
      debian_dockerfile = Rails.root.join(".dockerdev", "Dockerfile")
      alpine_dockerfile = Rails.root.join("ops", "pdf-extractor", "Dockerfile")
      production_dockerfile = Rails.root.join("docker", "dockerfiles", "production.alpine.dockerfile")

      unless debian_dockerfile.exist? && alpine_dockerfile.exist? && production_dockerfile.exist?
        abort "docker:lint:tessdata_parity: expected dockerfiles missing " \
          "(debian: #{debian_dockerfile.exist?}, alpine: #{alpine_dockerfile.exist?}, " \
          "production: #{production_dockerfile.exist?})"
      end

      debian_langs = DockerLintHelpers.extract_tesseract_langs(
        File.read(debian_dockerfile),
        package_prefix: "tesseract-ocr-",
        skip_bare_base: true
      )
      alpine_langs = DockerLintHelpers.extract_tesseract_langs(
        File.read(alpine_dockerfile),
        package_prefix: "tesseract-ocr-data-"
      )

      missing_in_alpine = debian_langs - alpine_langs
      missing_in_debian = alpine_langs - debian_langs

      if missing_in_alpine.any? || missing_in_debian.any?
        warn "Tesseract language package drift between dockerfiles:"
        warn "  Debian has, Alpine missing: #{missing_in_alpine.to_a.sort.inspect}" if missing_in_alpine.any?
        warn "  Alpine has, Debian missing: #{missing_in_debian.to_a.sort.inspect}" if missing_in_debian.any?
        abort "docker:lint:tessdata_parity: language sets diverge. Update both " \
          "dockerfiles together so dev (Debian) and ops/pdf-extractor (Alpine) extract the " \
          "same language coverage."
      end

      production_active = File.read(production_dockerfile)
        .each_line
        .reject { |line| line =~ /\A\s*#/ }
        .join

      if production_active.match?(/\bmupdf-tools\b|\btesseract-ocr|\bTESSDATA_PREFIX\b/)
        abort "docker:lint:tessdata_parity: production.alpine.dockerfile must not install " \
          "mupdf-tools or tesseract-ocr packages or set TESSDATA_PREFIX; PDF extraction " \
          "runs in the host ops/pdf-extractor service."
      end

      puts "docker:lint:tessdata_parity: tesseract language sets match across dockerfiles " \
        "(#{debian_langs.to_a.sort.inspect})."
    end

    # @lat: [[toolchain-pins#Toolchain pins#Why the dockerfile gates read every file and then read the running library]]
    desc "Assert SQLite build options match across dockerfiles and exclude unsafe ones"
    task :sqlite_flags do
      dockerfiles = (
        Rails.root.glob("docker/dockerfiles/*.dockerfile") +
          Rails.root.glob(".dockerdev/Dockerfile")
      ).sort

      production = Rails.root.join("docker", "dockerfiles", "production.alpine.dockerfile")
      unless production.exist?
        abort "docker:lint:sqlite_flags: production.alpine.dockerfile is missing. It was " \
          "renamed or removed; point this task and config/deploy.yml at the new name."
      end

      options = dockerfiles.to_h do |path|
        [path.relative_path_from(Rails.root).to_s,
          DockerLintHelpers.extract_sqlite_options(path.read)]
      end

      violations = options.transform_values { |set| DockerLintHelpers.forbidden_sqlite_options_in(set) }
        .reject { |_, found| found.empty? }

      if violations.any?
        warn "Forbidden SQLite build options found:"
        violations.each do |file, found|
          found.each { |name, reason| warn "  #{file}: -D#{name} #{reason}" }
        end
        abort "docker:lint:sqlite_flags: remove the options above. See the notes beside " \
          "the `bundle config set` line in production.alpine.dockerfile."
      end

      declaring = options.reject { |_, set| set.empty? }

      if declaring.empty? || !declaring.key?("docker/dockerfiles/production.alpine.dockerfile")
        abort "docker:lint:sqlite_flags: production.alpine.dockerfile sets no -DSQLITE_* " \
          "options. Two sets can only match by both being empty, which is how this gate " \
          "would go quiet without failing."
      end

      expected = declaring.values.first
      diverging = declaring.reject { |_, set| set == expected }

      if diverging.any?
        warn "SQLite build option drift between dockerfiles:"
        warn "  expected (#{declaring.keys.first}): #{expected.to_a.sort.inspect}"
        diverging.each { |file, set| warn "  #{file}: #{set.to_a.sort.inspect}" }
        abort "docker:lint:sqlite_flags: option sets diverge. Update every dockerfile " \
          "together so dev, CI and production compile the same SQLite."
      end

      puts "docker:lint:sqlite_flags: SQLite build options match across " \
        "#{declaring.size} dockerfile(s) (#{expected.to_a.sort.inspect})."
    end

    # @lat: [[toolchain-pins#Toolchain pins#Why the dockerfile gates read every file and then read the running library]]
    desc "Assert the SQLite loaded here matches what the dockerfiles compile"
    task :sqlite_runtime do
      require "sqlite3"

      production = Rails.root.join("docker", "dockerfiles", "production.alpine.dockerfile")
      unless production.exist?
        abort "docker:lint:sqlite_runtime: production.alpine.dockerfile is missing. It was " \
          "renamed or removed; point this task and config/deploy.yml at the new name."
      end

      declared = DockerLintHelpers.extract_sqlite_options(production.read)
      if declared.empty?
        abort "docker:lint:sqlite_runtime: production.alpine.dockerfile sets no -DSQLITE_* " \
          "options, so there is nothing to compare against and this check would pass on " \
          "anything. See docker:lint:sqlite_flags."
      end

      reported = SQLite3::Database.new(":memory:")
        .execute("PRAGMA compile_options")
        .flatten
        .to_set

      problems = DockerLintHelpers.sqlite_runtime_problems(declared: declared, reported: reported)

      if problems.any?
        warn "The SQLite compiled into this sqlite3 gem does not match the dockerfiles:"
        problems.each { |problem| warn "  this SQLite #{problem}" }
        abort <<~FIX
          docker:lint:sqlite_runtime: rebuild the gem with the options the images use.
            export BUNDLE_BUILD__SQLITE3="$(sed -n "s/.*\\(--with-sqlite-cflags='[^']*'\\).*/\\1/p" docker/dockerfiles/production.alpine.dockerfile)"
            bundle pristine sqlite3
          Setting the variable alone does nothing: bundle install leaves a gem
          that is already built exactly as it is.
        FIX
      end

      puts "docker:lint:sqlite_runtime: this SQLite matches the dockerfiles " \
        "(#{declared.to_a.sort.inspect})."
    end
  end
end
