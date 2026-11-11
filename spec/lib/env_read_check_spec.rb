# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../../lib/env_read_check"

# @lat: [[env-read-check-design#Why sway_lint_env_reads_rake_spec.rb stubs EnvReadCheck.new for its failure-path examples]]
RSpec.describe EnvReadCheck do
  def init_repo(dir)
    _, status = Open3.capture2("git", "-C", dir, "init", "-q")
    raise "git init failed under #{dir}" unless status.success?
  end

  def write_file(dir, relative_path, content)
    path = File.join(dir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  # Stages the file so `git ls-files` sees it -- no commit needed, `git add`
  # alone is enough to move a path into the index.
  def plant_tracked(dir, relative_path, content)
    path = write_file(dir, relative_path, content)
    _, status = Open3.capture2("git", "-C", dir, "add", relative_path)
    raise "git add failed for #{relative_path} under #{dir}" unless status.success?
    path
  end

  def plant_untracked(dir, relative_path, content)
    write_file(dir, relative_path, content)
  end

  # The one path #offences must never flag as a violation on its own --
  # planted in every example except the one proving what happens when it is
  # missing.
  def plant_allowed_path(dir)
    plant_tracked(dir, "app/lib/env_secret.rb", <<~RUBY)
      # frozen_string_literal: true
      module EnvSecret
        def self.read(name)
          ENV[name].to_s.strip.presence
        end
      end
    RUBY
  end

  it "reports a file holding a plain environment read once, with its path and the line the read is on" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_allowed_path(dir)
      plant_tracked(dir, "app/services/thing.rb", <<~RUBY)
        # frozen_string_literal: true
        class Thing
          def self.value
            ENV["A_SETTING"]
          end
        end
      RUBY

      thing_offences = described_class.new(dir).offences.select { |o| o.path == "app/services/thing.rb" }

      expect(thing_offences.length).to eq(1)
      expect(thing_offences.first.line).to eq(4)
    end
  end

  it "reports exactly one finding for a file mixing a real read with a look-alike line comment, block comment, and string" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_allowed_path(dir)
      plant_tracked(dir, "app/services/mixed.rb", <<~RUBY)
        # frozen_string_literal: true

        # ENV["LOOKS_LIKE_A_READ"] -- only in this comment
        LOOK_ALIKE = 'ENV["ALSO_NOT_A_READ"]'
        =begin
        ENV["STILL_NOT_A_READ"] -- inside a block comment
        =end
        REAL = ENV["THE_ONLY_REAL_READ"]
      RUBY

      mixed_offences = described_class.new(dir).offences.select { |o| o.path == "app/services/mixed.rb" }

      expect(mixed_offences.length).to eq(1)
      expect(mixed_offences.first.line).to eq(8)
    end
  end

  it "reports a read spread over several lines on the first line, where the bare word sits alone" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_allowed_path(dir)
      plant_tracked(dir, "app/services/multiline.rb", <<~RUBY)
        # frozen_string_literal: true

        VALUE = ENV
          .fetch("A_SETTING", "default")
      RUBY

      multiline_offences = described_class.new(dir).offences.select { |o| o.path == "app/services/multiline.rb" }

      expect(multiline_offences.length).to eq(1)
      expect(multiline_offences.first.line).to eq(3)
    end
  end

  it "never reads a file under the frontend directory, whatever its extension" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_allowed_path(dir)
      plant_tracked(dir, "app/frontend/sway_utils/scratch.rb", <<~RUBY)
        # frozen_string_literal: true
        LEFTOVER = ENV["SHOULD_NEVER_BE_SEEN"]
      RUBY

      offences = described_class.new(dir).offences

      expect(offences.map(&:path)).not_to include("app/frontend/sway_utils/scratch.rb")
    end
  end

  it "never reads an untracked file, so a scratch file cannot fail the check" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_allowed_path(dir)
      plant_untracked(dir, "app/services/scratch.rb", <<~RUBY)
        # frozen_string_literal: true
        LEFTOVER = ENV["SHOULD_NEVER_BE_SEEN"]
      RUBY

      offences = described_class.new(dir).offences

      expect(offences.map(&:path)).not_to include("app/services/scratch.rb")
    end
  end

  it "handles a template by compiling it first and maps the reported line back to the file's own numbering" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_allowed_path(dir)
      plant_tracked(dir, "app/views/example/show.html.erb", <<~ERB)
        <p>Hello</p>
        <%= ENV["SHOULD_NOT_BE_HERE"] %>
      ERB

      view_offences = described_class.new(dir).offences.select { |o| o.path == "app/views/example/show.html.erb" }

      expect(view_offences.length).to eq(1)
      expect(view_offences.first.line).to eq(2)
    end
  end

  it "fails with a message naming the missing path when the credential door is gone, rather than reporting a clean result" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      # app/lib/env_secret.rb deliberately never planted.

      expect { described_class.new(dir).offences }
        .to raise_error(EnvReadCheck::MissingAllowlistedPathError, /app\/lib\/env_secret\.rb/)
    end
  end

  # An allowlist nothing tests is the next silently-dead gate (this plan's
  # own stated risk). Not "contains the credential door" -- the EXACT set,
  # so a second entry quietly added later fails this example even though it
  # would still make every other example above pass.
  it "allows exactly one path: the credential door, and no other" do
    expect(EnvReadCheck::ALLOWED_PATHS).to eq(["app/lib/env_secret.rb"])
  end

  it "reports a file with an unrecognized extension via #skipped_paths, and excludes it from #offences" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_allowed_path(dir)
      plant_tracked(dir, "app/services/thing.mystery", <<~TEXT)
        ENV["THIS_IS_NOT_RUBY_SO_IT_IS_NEVER_PARSED"]
      TEXT

      check = described_class.new(dir)
      offences = check.offences

      expect(check.skipped_paths).to include("app/services/thing.mystery")
      expect(offences.map(&:path)).not_to include("app/services/thing.mystery")
    end
  end

  it "does not double-append to #skipped_paths when #offences is called twice" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_allowed_path(dir)
      plant_tracked(dir, "app/services/thing.mystery", "ENV[\"X\"]\n")

      check = described_class.new(dir)
      check.offences
      check.offences

      expect(check.skipped_paths.count("app/services/thing.mystery")).to eq(1)
    end
  end

  it "raises a plain error naming the root when git is not on PATH, rather than an unrescued Errno::ENOENT" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_allowed_path(dir)
      allow(Open3).to receive(:capture2).and_raise(Errno::ENOENT)

      expect { described_class.new(dir).offences }
        .to raise_error(RuntimeError, /git was not found on PATH/)
    end
  end

  # @lat: [[env-read-check-design#Why sway_lint_env_reads_rake_spec.rb stubs EnvReadCheck.new for its failure-path examples]]
  it "reports exactly one read against the real application, at the credential door, and that path is the allowed one" do
    real_root = File.expand_path("../..", __dir__.to_s)
    check = described_class.new(real_root)

    offences = check.offences

    expect(offences.length).to eq(1)
    expect(offences.first.path).to eq("app/lib/env_secret.rb")
    expect(check.allowed_paths).to include(offences.first.path)
  end

  # @lat: [[env-read-check-design#Why sway_lint_env_reads_rake_spec.rb stubs EnvReadCheck.new for its failure-path examples]]
  it "does not see an ENV read planted under lib/ -- the scan is scoped to app/ by decision" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_allowed_path(dir)
      plant_tracked(dir, "lib/example.rb", <<~RUBY)
        module Example
          def self.call
            ENV["OUTSIDE_APP"]
          end
        end
      RUBY

      offences = described_class.new(dir).offences

      expect(offences.map(&:path)).not_to include("lib/example.rb")
    end
  end

  it "lib/sway/legislation_test_isolation.rb is the one known lib/ file actually using the escape hatch" do
    real_root = File.expand_path("../..", __dir__.to_s)
    body = File.read(File.join(real_root, "lib/sway/legislation_test_isolation.rb"))

    expect(body).to match(/ENV\[/),
      "lib/sway/legislation_test_isolation.rb no longer reads ENV directly -- " \
      "update or remove this spec's documentation of the escape hatch"
  end
end
