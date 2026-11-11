module ConcurrencyHelpers
  # @lat: [[concurrency-helpers-raw-activerecord-fixture#Why seed_active_pipeline_run bypasses FactoryBot]]
  #
  # @param bill [Bill, nil] when given, the run covers that one bill (the model
  #   works out kind='single' from it); nil means a run over all bills.
  # @param status [String] "queued" or "running"
  # @return [LegislationPipelineRun]
  def seed_active_pipeline_run(bill: nil, status: "running")
    LegislationPipelineRun.create!(
      stages: [],
      bill: bill,
      status: status,
      started_at: Time.current
    )
  end
end

RSpec.configure do |config|
  config.include ConcurrencyHelpers
end
