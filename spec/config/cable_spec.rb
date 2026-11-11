# frozen_string_literal: true

require "rails_helper"
require "erb"
require "yaml"

# @lat: [[auxiliary-databases#Why Action Cable runs on Solid Cable, not Redis]]
RSpec.describe "config/cable.yml" do
  let(:config) do
    raw = Rails.root.join("config", "cable.yml").read
    YAML.safe_load(ERB.new(raw).result, aliases: true)
  end

  it "runs the environments that broadcast on Solid Cable, never Redis" do
    %w[development production].each do |env|
      adapter = config.fetch(env).fetch("adapter")

      expect(adapter).to eq("solid_cable"),
        "config/cable.yml #{env} adapter is #{adapter.inspect}. Sway runs no Redis " \
        "anywhere, so anything but solid_cable makes every broadcast raise and kill " \
        "the job behind it."
    end
  end

  # @lat: [[auxiliary-databases#Why cable messages don't live on the primary database]]
  it "sends the environments that broadcast to the cable database" do
    %w[development production].each do |env|
      target = config.fetch(env).dig("connects_to", "database", "writing")

      expect(target).to eq("cable"),
        "config/cable.yml #{env} writes broadcasts to #{target.inspect}. Solid Cable " \
        "belongs on its own database — on the primary it takes the same SQLite write " \
        "lock as user votes, once per pipeline state change and once per bill."
    end
  end

  # Test is the deliberate exception: the in-memory adapter writes no rows, so
  # there is nothing to keep off the primary database.
  it "gives the test environment no cable database to write to" do
    expect(config.fetch("test")).not_to have_key("connects_to")
  end

  # A broadcast in a spec must not write rows into the shared test database.
  # The test adapter keeps messages in memory, which is also what
  # have_broadcasted_to reads.
  it "keeps the in-memory adapter for tests" do
    expect(config.fetch("test").fetch("adapter")).to eq("test")
  end

  # @lat: [[auxiliary-databases#Why cable and cache are provisioned by a migrations path]]
  it "provisions the messages table from the deploy's own migrations" do
    database_config = YAML.safe_load(
      ERB.new(Rails.root.join("config", "database.yml").read).result,
      aliases: true
    )

    config.each_pair do |env, settings|
      next unless settings.is_a?(Hash)

      target = settings.dig("connects_to", "database", "writing")
      # No connects_to: the table is ordinary primary-database work, which
      # db:migrate already does on every deploy. Nothing more to check.
      next if target.blank?

      declared = database_config.fetch(env, {})[target.to_s]
      expect(declared).to be_a(Hash),
        "config/cable.yml #{env} sends cable to the #{target.inspect} database, which " \
        "config/database.yml never declares for #{env}."

      expect(declared["migrations_paths"]).to be_present,
        "config/cable.yml #{env} sends cable to the #{target.inspect} database and that " \
        "database has no migrations_paths. db:migrate will not create its table, so a " \
        "machine built from an empty disk gets no table and the deploy fails without " \
        "saying why. Give it a migrations folder, the way queue has " \
        "db/queue_migrate."
    end
  end

  # @lat: [[auxiliary-databases#What sets the cable polling interval and its retention]]
  describe "the poll" do
    # Parsed the way Solid Cable parses these. A lambda, not a def: a def inside
    # a describe block is metaprogramming Steep cannot see.
    seconds = lambda do |value|
      *amount, units = value.to_s.split(".")
      amount.join(".").to_f.public_send(units).to_f
    end

    # Below the chosen value, not at it, so latency can still be bought back
    # with CPU. It is here to catch a silent return to the gem's 0.1s default.
    fastest_worth_paying_for = 0.2

    # @lat: [[cable-poll-interval-convergence-budget#Why spec/config/cable_spec.rb bounds polling_interval at half a second]]
    convergence_budget = 1.0
    slowest_that_keeps_the_promise = convergence_budget / 2

    it "polls fast enough to keep the one-second convergence promise" do
      %w[development production].each do |env|
        interval = seconds.call(config.fetch(env).fetch("polling_interval"))

        expect(interval).to be <= slowest_that_keeps_the_promise,
          "config/cable.yml #{env} polls every #{interval}s, so a broadcast can wait " \
          "that long before anyone sees it, and the partial reload it triggers still " \
          "has to happen after that. The pipeline screens were specified to converge " \
          "within #{convergence_budget}s. Slowing the poll past " \
          "#{slowest_that_keeps_the_promise}s breaks that promise — if the promise " \
          "itself has changed, change it here and in the spec that states it."
      end
    end

    it "does not poll faster than the Pi can afford" do
      %w[development production].each do |env|
        interval = seconds.call(config.fetch(env).fetch("polling_interval"))

        expect(interval).to be >= fastest_worth_paying_for,
          "config/cable.yml #{env} polls every #{interval}s. Measured, the gem's " \
          "0.1s default costs 4.0% of one core per process holding a subscriber on a " \
          "fast workstation, which is roughly a fifth of a core per Puma worker on the Pi. If " \
          "the hardware changed, move this floor and say why."
      end
    end

    # Trimming deletes anything older than the retention window, so a listener
    # that pauses for longer than it loses messages.
    it "keeps messages far longer than a poll cycle" do
      %w[development production].each do |env|
        settings = config.fetch(env)
        interval = seconds.call(settings.fetch("polling_interval"))
        retention = seconds.call(settings.fetch("message_retention"))

        expect(retention).to be >= interval * 60,
          "config/cable.yml #{env} keeps messages #{retention}s and polls every " \
          "#{interval}s. Trimming would then be deleting rows a listener that paused " \
          "briefly has not read yet. Keep retention a wide multiple of the interval."
      end
    end
  end

  columns_in = ->(path) { File.read(path.to_s).scan(/t\.\w+ "([a-z_]+)"/).flatten.sort }

  # Drift guard: if a Solid Cable release adds or renames a column, the symptom
  # is otherwise a broadcast failing at run time.
  it "has every column Solid Cable itself ships" do
    template = Rails.root.join(
      Gem::Specification.find_by_name("solid_cable").gem_dir,
      "lib", "generators", "solid_cable", "install", "templates", "db", "cable_schema.rb"
    )

    expect(File.exist?(template)).to be(true),
      "Cannot find the schema Solid Cable ships, so there is nothing to compare against. " \
      "The gem moved it; find the new path rather than deleting this example. Looked in: #{template}"

    expected = columns_in.call(template)
    expect(expected).not_to be_empty,
      "Read Solid Cable's own schema and found no columns in it, so this comparison proves nothing."

    # @lat: [[auxiliary-databases#The cable move ships in two deploys]]
    actual = columns_in.call(Rails.root.join("db", "cable_schema.rb"))

    expect(actual).to include(*expected), <<~MESSAGE
      db/cable_schema.rb is missing columns Solid Cable expects: #{(expected - actual).inspect}

      Solid Cable was probably upgraded. Generate the update migration rather than
      hand-editing the schema file:  bin/rails generate solid_cable:update
      Move the generated file into db/cable_migrate, which is where the cable
      database takes its migrations from, then run db:migrate to redump the schema.
    MESSAGE
  end
end
