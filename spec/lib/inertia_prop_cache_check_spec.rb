# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../lib/inertia_prop_cache_check"

RSpec.describe InertiaPropCacheCheck do
  def write_file(dir, relative_path, content)
    path = File.join(dir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  it "reports a once-prop with no discriminator in its key" do
    Dir.mktmpdir do |dir|
      write_file(dir, "app/controllers/things_controller.rb", <<~RUBY)
        class ThingsController < ApplicationController
          def index
            render inertia: "Things", props: {
              sway_locales: InertiaRails.once(key: "sway_locales") { SwayLocale.all }
            }
          end
        end
      RUBY

      offences = described_class.new(dir).offences

      expect(offences.map(&:path)).to eq(["app/controllers/things_controller.rb"])
      expect(offences.first.line).to eq(4)
    end
  end

  it "reports a cached prop keyed on the page rather than on who is asking" do
    Dir.mktmpdir do |dir|
      write_file(dir, "app/controllers/things_controller.rb", <<~RUBY)
        class ThingsController < ApplicationController
          def index
            render inertia: "Things", props: {
              options: InertiaRails.cache(cache: {key: "thing_options", expires_in: 1.minute}) { options }
            }
          end
        end
      RUBY

      expect(described_class.new(dir).offences.length).to eq(1)
    end
  end

  it "reports a cache: option riding a prop of another kind" do
    Dir.mktmpdir do |dir|
      write_file(dir, "app/controllers/things_controller.rb", <<~RUBY)
        class ThingsController < ApplicationController
          def index
            render inertia: "Things", props: {
              rows: InertiaRails.defer(cache: "thing_rows") { rows }
            }
          end
        end
      RUBY

      expect(described_class.new(dir).offences.length).to eq(1)
    end
  end

  it "passes a key that carries who the props belong to" do
    Dir.mktmpdir do |dir|
      write_file(dir, "app/controllers/things_controller.rb", <<~RUBY)
        class ThingsController < ApplicationController
          def index
            render inertia: "Things", props: {
              options: InertiaRails.cache(cache: {key: ["thing_options", current_user.id], expires_in: 1.minute}) { options }
            }
          end
        end
      RUBY

      expect(described_class.new(dir).offences).to be_empty
    end
  end

  it "passes a key scoped by locale" do
    Dir.mktmpdir do |dir|
      write_file(dir, "app/controllers/things_controller.rb", <<~RUBY)
        class ThingsController < ApplicationController
          def index
            render inertia: "Things", props: {
              rows: InertiaRails.once(key: "rows:\#{sway_locale.id}") { rows }
            }
          end
        end
      RUBY

      expect(described_class.new(dir).offences).to be_empty
    end
  end

  # A key built from a column name glues the scope word to what follows it.
  {
    "sway_locale_id" => %(InertiaRails.once(key: "rows:\#{sway_locale_id}") { rows }),
    "current_user_id" => %(InertiaRails.cache(cache: {key: ["rows", current_user_id]}) { rows }),
    "locale_id" => %(InertiaRails.once(key: "rows:\#{locale_id}") { rows }),
    "user.id" => %(InertiaRails.once(key: "rows:\#{current_user.id}") { rows })
  }.each do |column, call|
    it "passes a key built from #{column}" do
      Dir.mktmpdir do |dir|
        write_file(dir, "app/controllers/things_controller.rb", <<~RUBY)
          class ThingsController < ApplicationController
            def index
              render inertia: "Things", props: {rows: #{call}}
            end
          end
        RUBY

        expect(described_class.new(dir).offences).to be_empty
      end
    end
  end

  it "reports a key naming the collection rather than one reader's place in it" do
    Dir.mktmpdir do |dir|
      write_file(dir, "app/controllers/things_controller.rb", <<~RUBY)
        class ThingsController < ApplicationController
          def index
            render inertia: "Things", props: {
              sway_locales: InertiaRails.once(key: "sway_locales") { SwayLocale.all }
            }
          end
        end
      RUBY

      expect(described_class.new(dir).offences.length).to eq(1)
    end
  end

  it "reports a key whose only scope word is glued to the end of another word" do
    Dir.mktmpdir do |dir|
      write_file(dir, "app/controllers/things_controller.rb", <<~RUBY)
        class ThingsController < ApplicationController
          def index
            render inertia: "Things", props: {
              rows: InertiaRails.once(key: "abuser_rows") { rows }
            }
          end
        end
      RUBY

      expect(described_class.new(dir).offences.length).to eq(1)
    end
  end

  it "passes the bootstrap pattern, which caches the shared part and merges the rest in after" do
    Dir.mktmpdir do |dir|
      write_file(dir, "app/controllers/api/v1/bootstrap_controller.rb", <<~RUBY)
        module Api
          module V1
            class BootstrapController < ApplicationController
              def show
                botm_json = Rails.cache.fetch("api_v1_bootstrap:botm:\#{locale&.id}", expires_in: 60) do
                  Bill.of_the_month(sway_locale: locale)&.to_sway_json
                end

                render json: {
                  bill_of_the_month: botm_json&.merge(user_vote: current_user_vote)
                }
              end
            end
          end
        end
      RUBY

      expect(described_class.new(dir).offences).to be_empty
    end
  end

  it "reads no file under app/frontend" do
    Dir.mktmpdir do |dir|
      write_file(dir, "app/frontend/entrypoints/thing.rb", <<~RUBY)
        InertiaRails.once(key: "anything")
      RUBY

      check = described_class.new(dir)

      expect(check.scanned_paths).to be_empty
      expect(check.offences).to be_empty
    end
  end

  it "finds no offence in this repository" do
    root = File.expand_path("../..", __dir__.to_s)

    expect(described_class.new(root).offences.map(&:to_s)).to be_empty
  end
end
