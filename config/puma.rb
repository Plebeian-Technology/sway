Rails.logger.info(
  "\n##################################################################\n"
)
Rails.logger.info("Puma starting with RAILS_ENV = #{ENV.fetch("RAILS_ENV")}")
Rails.logger.info(
  "\n##################################################################\n"
)

threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

# @lat: [[puma-worker-concurrency-model#The GVL limitation]]
web_concurrency = ENV.fetch("WEB_CONCURRENCY", 0).to_i
if web_concurrency.positive?
  workers web_concurrency
  preload_app!

  # @lat: [[puma-worker-concurrency-model#SQLite connection lifecycle across forked workers]]
  before_fork do
    ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord::Base)
    # @lat: [[puma-worker-concurrency-model#Pre-fork VM warmup]]
    Process.warmup if Process.respond_to?(:warmup)
  end
  # @lat: [[puma-worker-concurrency-model#SQLite connection lifecycle across forked workers]]
  before_worker_boot do
    ActiveRecord::Base.establish_connection if defined?(ActiveRecord::Base)
  end
end

# @lat: [[puma-worker-concurrency-model#Plain HTTP in production versus local TLS binding]]
if ENV["RAILS_ENV"] == "production"
  port ENV.fetch("PORT", 3333)
else
  ssl_bind "0.0.0.0",
    ENV.fetch("PORT", 3333),
    {
      key: "config/ssl/key.pem",
      cert: "config/ssl/cert.pem",
      verify_mode: "none"
    }
end

plugin :tmp_restart

# @lat: [[puma-worker-concurrency-model#Why background jobs don't run inside this web server]]
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
