# frozen_string_literal: true

class ReportingEndpointsMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    headers["Reporting-Endpoints"] = 'csp-endpoint="/csp-report"'
    %w[Content-Security-Policy Content-Security-Policy-Report-Only].each do |h|
      if headers[h].present? && !headers[h].include?("report-to")
        headers[h] = "#{headers[h]}; report-to csp-endpoint"
      end
    end
    [status, headers, body]
  end
end
