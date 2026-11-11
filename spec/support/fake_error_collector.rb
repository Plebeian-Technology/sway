# frozen_string_literal: true

# @lat: [[fake-error-collector-design#Why FakeErrorCollector checks the wire, not the object]]
class FakeErrorCollector
  # What the collector answers with instead of storing the report. The app is
  # told nothing useful, which is why these are so expensive to find by hand.
  class Refused < StandardError; end

  GZIP = "gzip"

  # A report is one "envelope": a header line, then pairs of lines describing
  # and carrying each item. An error is an item of type "event".
  EVENT_ITEM_TYPE = "event"

  # Reads one request the way the collector does. Hands back the error it found,
  # or nil when the envelope carried something else, such as a session. Raises
  # Refused with the reason the collector would give.
  def receive(headers, body)
    lines = decode(headers, body).split("\n").reject(&:empty?)
    raise Refused, "the envelope was empty" if lines.empty?

    check_envelope_header(parse(lines.first.to_s, "envelope header"))
    event = find_event(lines.drop(1))
    check_event(event) if event
    event
  end

  private

  # THE ONE THAT COST THE MOST. sentry-ruby sets Content-Encoding on every
  # request and leaves it EMPTY when the body is under its 30KB gzip threshold.
  # An ABSENT header means "not compressed" and is fine. An EMPTY one names an
  # encoding nobody knows, so the collector answers 400 and the error is gone.
  def decode(headers, body)
    encoding = find_header(headers, "Content-Encoding")

    return body.to_s if encoding.nil?
    raise Refused, "Unsupported Content-Encoding: #{encoding.inspect}" unless encoding == GZIP

    begin
      Zlib.gunzip(body.to_s.b)
    rescue Zlib::Error => e
      raise Refused, "said gzip and was not: #{e.class}"
    end
  end

  # Header names arrive in whatever capitalisation the client chose.
  def find_header(headers, name)
    pair = headers.find { |key, _| key.to_s.casecmp?(name) }
    pair&.last
  end

  def parse(line, what)
    parsed = JSON.parse(line)
    raise Refused, "#{what} is not an object" unless parsed.is_a?(Hash)

    parsed
  rescue JSON::ParserError => e
    raise Refused, "#{what} is not JSON: #{e.message}"
  end

  # A rewritten event_id is not an id. The collector drops the whole envelope
  # and says nothing, so roughly one error in twenty-eight would simply vanish.
  # This is how the scrubber's reach over protocol fields gets caught.
  def check_envelope_header(header)
    id = header["event_id"].to_s
    return if /\A[0-9a-f]{32}\z/.match?(id)

    raise Refused, "event_id is not 32 hex characters: #{id.inspect}"
  end

  # Items come in pairs: a line saying what the next line is, then the thing.
  def find_event(lines)
    lines.each_slice(2) do |pair|
      description = pair[0]
      payload = pair[1]
      next if description.nil? || payload.nil?
      next unless parse(description, "item header")["type"] == EVENT_ITEM_TYPE

      return parse(payload, "event")
    end
    nil
  end

  def check_event(event)
    check_request_shape(event["request"])
    check_fingerprint(event["fingerprint"])
  end

  # Sentry declares these as maps. Android's native code casts them, so a string
  # here throws inside its reader and destroys the whole error with nothing said
  # in the app. The collector itself accepts a string, which is exactly why only
  # one of three clients ever complained.
  def check_request_shape(request)
    return unless request.is_a?(Hash)

    %w[headers cookies].each do |field|
      value = request[field]
      next if value.nil? || value.is_a?(Hash)

      raise Refused, "request.#{field} must be a map, got #{value.class}"
    end
  end

  # An empty list here reads as "the app chose a fingerprint" rather than "chose
  # none", so every error collapses into one issue. Ruby sends it on every event
  # and Android sent it too; iOS omits the key.
  def check_fingerprint(fingerprint)
    return unless fingerprint.is_a?(Array) && fingerprint.empty?

    raise Refused, "fingerprint is an empty list, which groups every error together"
  end
end
