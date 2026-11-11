# frozen_string_literal: true

# @lat: [[bad-request-responses#Rack's own bad-request family answers 400]]
class BadRequestMiddleware
  BODY = "Bad Request\n"

  def initialize(app)
    @app = app
  end

  def call(env)
    @app.call(env)
  rescue Rack::BadRequest => e
    SwayLogging.warn(
      "bad_request.rejected",
      request_path: env["PATH_INFO"],
      error_class: e.class.name
    )

    [
      400,
      {
        "content-type" => "text/plain; charset=utf-8",
        "content-length" => BODY.bytesize.to_s
      },
      [BODY]
    ]
  end
end
