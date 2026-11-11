# frozen_string_literal: true

require "rails_helper"
require "erb"
require "yaml"

# @lat: [[queue-worker-poll-order#Why every real ApplicationJob's queue is checked against the poll list]]
RSpec.describe "config/queue.yml" do
  let(:config) do
    raw = Rails.root.join("config", "queue.yml").read
    YAML.safe_load(ERB.new(raw).result, aliases: true)
  end

  it "polls an ordered queue list with default first, background included, no wildcard" do
    queues = config.fetch("production").fetch("workers").first.fetch("queues")

    expect(queues).to be_an(Array)
    expect(queues.first).to eq("default")
    expect(queues).to include("background")
    expect(queues).not_to include("*")
  end

  it "polls every queue that an ApplicationJob enqueues onto" do
    Rails.application.eager_load!
    worker_queues = config.fetch("production").fetch("workers").flat_map { |w| Array(w.fetch("queues")) }

    ApplicationJob.descendants.each do |klass|
      source = klass.name && Object.const_source_location(klass.name)&.first
      next unless source&.start_with?(Rails.root.join("app").to_s)

      queue = klass.queue_name
      next if queue.blank?

      expect(worker_queues).to include(queue.to_s),
        "#{klass} enqueues on #{queue.inspect} which no worker polls — it will never run"
    end
  end
end
