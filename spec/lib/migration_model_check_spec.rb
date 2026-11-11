# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../lib/migration_model_check"

RSpec.describe MigrationModelCheck do
  def write_file(dir, relative_path, content)
    path = File.join(dir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def plant_model(dir)
    write_file(dir, "app/models/legislator.rb", <<~RUBY)
      class Legislator < ApplicationRecord
      end
    RUBY
  end

  def plant_allowlisted_migration(dir, path)
    write_file(dir, path, <<~RUBY)
      class Placeholder < ActiveRecord::Migration[8.1]
      end
    RUBY
  end

  def plant_named_paths(dir)
    MigrationModelCheck::ALLOWED_REFERENCES.each_key { |path| plant_allowlisted_migration(dir, path) }
  end

  it "reports a migration that names a model class, with the line it is named on" do
    Dir.mktmpdir do |dir|
      plant_model(dir)
      plant_named_paths(dir)
      write_file(dir, "db/migrate/20260101000001_backfill_legislators.rb", <<~RUBY)
        class BackfillLegislators < ActiveRecord::Migration[8.1]
          def up
            Legislator.update_all(active: true)
          end
        end
      RUBY

      offences = described_class.new(dir).offences

      expect(offences.map(&:to_s)).to eq(
        ["db/migrate/20260101000001_backfill_legislators.rb:3 names Legislator"]
      )
    end
  end

  it "passes a migration that defines its own stand-in for the same table" do
    Dir.mktmpdir do |dir|
      plant_model(dir)
      plant_named_paths(dir)
      write_file(dir, "db/migrate/20260101000001_backfill_legislators.rb", <<~RUBY)
        class BackfillLegislators < ActiveRecord::Migration[8.1]
          class MigrationLegislator < ActiveRecord::Base
            self.table_name = "legislators"
          end

          def up
            MigrationLegislator.update_all(active: true)
          end
        end
      RUBY

      expect(described_class.new(dir).offences).to be_empty
    end
  end

  it "passes a migration that redefines the model's own name inside itself" do
    Dir.mktmpdir do |dir|
      plant_model(dir)
      plant_named_paths(dir)
      write_file(dir, "db/data/20260101000001_backfill_legislators.rb", <<~RUBY)
        class BackfillLegislators < ActiveRecord::Migration[8.1]
          class Legislator < ActiveRecord::Base
            self.table_name = "legislators"
          end

          def up
            Legislator.update_all(active: true)
          end
        end
      RUBY

      expect(described_class.new(dir).offences).to be_empty
    end
  end

  it "reads a qualified reference whole rather than as its leading segment" do
    Dir.mktmpdir do |dir|
      write_file(dir, "app/models/sway_locale/term_rules_registry.rb", <<~RUBY)
        class SwayLocale
          class TermRulesRegistry
          end
        end
      RUBY
      plant_named_paths(dir)
      write_file(dir, "db/migrate/20260101000001_read_the_registry.rb", <<~RUBY)
        class ReadTheRegistry < ActiveRecord::Migration[8.1]
          def up
            SwayLocale::TermRulesRegistry.declared?("baltimore-maryland-united_states")
          end
        end
      RUBY

      offences = described_class.new(dir).offences

      expect(offences.map(&:constant_name)).to eq(["SwayLocale::TermRulesRegistry"])
    end
  end

  it "refuses to report zero when a path it names has been renamed away" do
    Dir.mktmpdir do |dir|
      plant_model(dir)

      expect { described_class.new(dir).offences }
        .to raise_error(MigrationModelCheck::MissingAllowlistedPathError, /no longer exist/)
    end
  end

  it "finds no offence in this repository's own migrations" do
    root = File.expand_path("../..", __dir__.to_s)

    expect(described_class.new(root).offences.map(&:to_s)).to be_empty
  end
end
