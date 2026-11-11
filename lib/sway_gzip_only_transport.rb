# frozen_string_literal: true

# @lat: [[local-error-reporting-design#Why SwayGzipOnlyTransport always compresses]]
class SwayGzipOnlyTransport < Sentry::HTTPTransport
  private

  def should_compress?(_data)
    true
  end
end
