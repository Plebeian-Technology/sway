# frozen_string_literal: true

require "rails_helper"
require "rake"
require "tmpdir"
require "fileutils"
require "open3"

# @lat: [[verification-gates#Docker lanes]]
RSpec.describe "sway:lint:rspec_constants" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("sway:lint:rspec_constants")
  end

  before do
    Rake::Task["sway:lint:rspec_constants"].reenable if Rake::Task.task_defined?("sway:lint:rspec_constants")
  end

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

  def plant_tracked(dir, relative_path, content)
    path = write_file(dir, relative_path, content)
    _, status = Open3.capture2("git", "-C", dir, "add", relative_path)
    raise "git add failed for #{relative_path} under #{dir}" unless status.success?
    path
  end

  it "fails and names the offending file when code rescues RSpec::Mocks::MockExpectationError" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_tracked(dir, "app/services/bad.rb", <<~RUBY)
        # frozen_string_literal: true

        class Bad
          def call
            yield
          rescue RSpec::Mocks::MockExpectationError => e
            nil
          end
        end
      RUBY

      expect do
        Rake::Task["sway:lint:rspec_constants"].invoke(dir)
      end.to raise_error(SystemExit).and output(/app\/services\/bad\.rb:6/).to_stderr
    end
  end

  it "passes on a clean git repository containing no RSpec constants" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_tracked(dir, "app/models/clean.rb", <<~RUBY)
        # frozen_string_literal: true

        class Clean
          def call
            :ok
          end
        end
      RUBY

      expect { Rake::Task["sway:lint:rspec_constants"].invoke(dir) }.not_to raise_error
    end
  end

  it "passes against the real repository tree where no production code names an RSpec constant" do
    expect { Rake::Task["sway:lint:rspec_constants"].invoke }.not_to raise_error
  end

  it "flags bare RSpec constant references" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_tracked(dir, "app/services/bare.rb", <<~RUBY)
        # frozen_string_literal: true

        class Bare
          def check
            RSpec
          end
        end
      RUBY

      expect do
        Rake::Task["sway:lint:rspec_constants"].invoke(dir)
      end.to raise_error(SystemExit).and output(/app\/services\/bare\.rb:5/).to_stderr
    end
  end

  it "flags top-level ::RSpec references" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_tracked(dir, "app/services/top_level.rb", <<~RUBY)
        # frozen_string_literal: true

        class TopLevel
          def check
            ::RSpec::Mocks
          end
        end
      RUBY

      expect do
        Rake::Task["sway:lint:rspec_constants"].invoke(dir)
      end.to raise_error(SystemExit).and output(/app\/services\/top_level\.rb:5/).to_stderr
    end
  end

  it "does not flag Foo::RSpec where RSpec is not the root constant" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_tracked(dir, "app/services/nested.rb", <<~RUBY)
        # frozen_string_literal: true

        class Nested
          def check
            Foo::RSpec
          end
        end
      RUBY

      expect { Rake::Task["sway:lint:rspec_constants"].invoke(dir) }.not_to raise_error
    end
  end

  it "does not flag RSpec inside string literals, symbols, or comments" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_tracked(dir, "app/services/literal.rb", <<~RUBY)
        # frozen_string_literal: true

        # Comment mentioning RSpec
        class Literal
          NAME = "RSpec"
          SYM = :RSpec
        end
      RUBY

      expect { Rake::Task["sway:lint:rspec_constants"].invoke(dir) }.not_to raise_error
    end
  end

  it "flags RSpec constant references in lib/ files as well as app/" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_tracked(dir, "lib/bad_task.rake", <<~RUBY)
        # frozen_string_literal: true

        task :bad do
          RSpec.describe
        end
      RUBY

      expect do
        Rake::Task["sway:lint:rspec_constants"].invoke(dir)
      end.to raise_error(SystemExit).and output(/lib\/bad_task\.rake:4/).to_stderr
    end
  end

  it "ignores files under app/frontend/" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_tracked(dir, "app/frontend/bad.rb", <<~RUBY)
        # frozen_string_literal: true

        RSpec
      RUBY

      expect { Rake::Task["sway:lint:rspec_constants"].invoke(dir) }.not_to raise_error
    end
  end

  it "flags RSpec in conditional or-assignment" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_tracked(dir, "app/services/or_write.rb", <<~RUBY)
        # frozen_string_literal: true

        RSpec ||= Module.new
      RUBY

      expect do
        Rake::Task["sway:lint:rspec_constants"].invoke(dir)
      end.to raise_error(SystemExit).and output(/app\/services\/or_write\.rb:3/).to_stderr
    end
  end

  it "flags RSpec in conditional and-assignment" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_tracked(dir, "app/services/and_write.rb", <<~RUBY)
        # frozen_string_literal: true

        RSpec &&= nil
      RUBY

      expect do
        Rake::Task["sway:lint:rspec_constants"].invoke(dir)
      end.to raise_error(SystemExit).and output(/app\/services\/and_write\.rb:3/).to_stderr
    end
  end

  it "flags RSpec in operator assignment" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_tracked(dir, "app/services/op_write.rb", <<~RUBY)
        # frozen_string_literal: true

        RSpec += 1
      RUBY

      expect do
        Rake::Task["sway:lint:rspec_constants"].invoke(dir)
      end.to raise_error(SystemExit).and output(/app\/services\/op_write\.rb:3/).to_stderr
    end
  end

  it "flags top-level ::RSpec in multiple assignment targets" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_tracked(dir, "app/services/multi_top.rb", <<~RUBY)
        # frozen_string_literal: true

        ::RSpec, a = 1, 2
      RUBY

      expect do
        Rake::Task["sway:lint:rspec_constants"].invoke(dir)
      end.to raise_error(SystemExit).and output(/app\/services\/multi_top\.rb:3/).to_stderr
    end
  end

  it "flags RSpec constant paths in multiple assignment targets" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_tracked(dir, "app/services/multi_path.rb", <<~RUBY)
        # frozen_string_literal: true

        RSpec::Foo, a = 1, 2
      RUBY

      expect do
        Rake::Task["sway:lint:rspec_constants"].invoke(dir)
      end.to raise_error(SystemExit).and output(/app\/services\/multi_path\.rb:3/).to_stderr
    end
  end

  it "does not flag Foo::RSpec in multiple assignment targets" do
    Dir.mktmpdir do |dir|
      init_repo(dir)
      plant_tracked(dir, "app/services/multi_nested.rb", <<~RUBY)
        # frozen_string_literal: true

        Foo::RSpec, a = 1, 2
      RUBY

      expect { Rake::Task["sway:lint:rspec_constants"].invoke(dir) }.not_to raise_error
    end
  end
end
