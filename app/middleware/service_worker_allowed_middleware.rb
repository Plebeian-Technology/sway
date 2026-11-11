# frozen_string_literal: true

# @lat: [[service-worker-allowed-scope-and-caching#Service-Worker-Allowed: /]]
class ServiceWorkerAllowedMiddleware
  PATHS = %r{\A/vite(-dev|-test)?(/run-[^/]+)?/sw\.js\z}

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    if PATHS.match?(env["PATH_INFO"])
      headers["Service-Worker-Allowed"] = "/"
      headers["Cache-Control"] = "no-cache"
    end
    [status, headers, body]
  end
end
