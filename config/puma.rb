# typed: false

# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.

# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# The ideal number of threads per worker depends both on how much time the
# application spends waiting for IO operations and on how much you wish to
# to prioritize throughput over latency.
#
# As a rule of thumb, increasing the number of threads will increase how much
# traffic a given process can handle (throughput), but due to CRuby's
# Global VM Lock (GVL) it has diminishing returns and will degrade the
# response time (latency) of the application.
#
# The default is set to 3 threads as it's deemed a decent compromise between
# throughput and latency for the average Rails application.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads. This includes Active Record's `pool` parameter in `database.yml`.

Rails.logger.info("\n##################################################################\n")
Rails.logger.info("Puma starting with RAILS_ENV = #{ENV.fetch("RAILS_ENV")}")
Rails.logger.info("\n##################################################################\n")

threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

# Specifies the `port` that Puma will listen on to receive requests; default is 3333.
if ENV["RAILS_ENV"] == "production"
  port ENV.fetch("PORT") { 3333 }
else
  ssl_bind "0.0.0.0", ENV.fetch("PORT", 3333), {
    key: "config/ssl/key.pem",
    cert: "config/ssl/cert.pem",
    verify_mode: "none"
  }
end

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# You can either set the env var, or check for development
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
