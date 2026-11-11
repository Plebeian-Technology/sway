# frozen_string_literal: true

require "rails_helper"

# @lat: [[queue-schema-regeneration-risk#The check and the recovery]]
RSpec.describe "db/queue_schema.rb" do
  it "defines every table Solid Queue ships, so a machine built from nothing gets them" do
    template = Rails.root.join(
      Gem::Specification.find_by_name("solid_queue").gem_dir,
      "lib", "generators", "solid_queue", "install", "templates", "db", "queue_schema.rb"
    )

    expect(File.exist?(template)).to be(true),
      "Cannot find the schema Solid Queue ships, so there is nothing to compare against. " \
      "The gem moved it; find the new path rather than deleting this example. Looked in: #{template}"

    expected = File.read(template).scan(/create_table "([a-z_]+)"/).flatten.sort
    actual = Rails.root.join("db", "queue_schema.rb").read.scan(/create_table "([a-z_]+)"/).flatten.sort

    expect(expected).not_to be_empty,
      "Read Solid Queue's own schema and found no tables in it, so this comparison proves nothing."

    expect(actual).to include(*expected), <<~MESSAGE
      db/queue_schema.rb is missing tables that Solid Queue needs: #{(expected - actual).inspect}

      If the file now holds no tables at all, it was almost certainly overwritten by
      applying migrations in development against a job database that was never set up.
      Restore it with:  git checkout -- db/queue_schema.rb

      If Solid Queue was just upgraded and added a table, regenerate instead:
      bin/rails generate solid_queue:install
    MESSAGE
  end
end
