# frozen_string_literal: true

module SwayLogging
  SENSITIVE_KEYS = %w[
    authorization
    cookie
    token
    secret
    password
    credential
    passkey
    public_key
    private_key
    api_key
    secret_key
    auth_token
    email
    phone
    auth
    code
    refresh_token
    access_token
    to
    from
    body
    street
    postal_code
    latitude
    longitude
    full_name
  ].freeze
  SENSITIVE_KEY_PATTERN =
    /(?:_key|_token)\z|(?:^|_)(?:secret|password|passwd|phone|email|street|postal_code|latitude|longitude|full_name)(?:_|\z)/i
  MAX_VALUE_CHARS = 200

  # @lat: [[sway-logging-design#Why .redact_anthropic_key exists separately from Rails' filter]]
  ANTHROPIC_KEY_REGEXP = /sk-ant-[A-Za-z0-9_-]+/

  module_function

  # @lat: [[console-channels#Console channels in the browser#Why the server logger keeps a debug-level twin]]
  def debug(event, **metadata)
    Rails.logger.debug(format_event(event, metadata))
  end

  def info(event, **metadata)
    Rails.logger.info(format_event(event, metadata))
  end

  def warn(event, **metadata)
    Rails.logger.warn(format_event(event, metadata))
  end

  def error(event, **metadata)
    Rails.logger.error(format_event(event, metadata))
  end

  # @lat: [[sway-logging-design#What .log_exception protects against]]
  def log_exception(event, exception:, level: :error, **metadata)
    redacted_message = redact_anthropic_key(exception.message)
    redacted_full_message = redact_anthropic_key(
      exception.full_message(highlight: false, order: :top)
    )

    public_send(
      level,
      event,
      **metadata.merge(
        error_class: exception.class.name,
        error_message: compact_message(redacted_message)
      )
    )
    Rails.logger.public_send(level, redacted_full_message)
  end

  def summarize(value)
    case value
    when ActiveRecord::Base
      "#{value.class.name}(id=#{value.id})"
    when Array
      preview = value.first(5).map { |item| summarize(item) }
      "#{preview.inspect}#{"...(#{value.size} items)" if value.size > 5}"
    when Hash
      # @lat: [[sway-logging-design#Why .summarize's Hash branch redacts at every nesting level]]
      value
        .transform_keys(&:to_s)
        .slice(*value.keys.first(10).map(&:to_s))
        .each_with_object({}) do |(k, v), scrubbed|
          scrubbed[k] = sensitive_key?(k) ? "[FILTERED]" : summarize(v)
        end
    else
      value
    end
  end

  def sensitive_key?(key)
    k = key.to_s.downcase
    SENSITIVE_KEYS.include?(k) || SENSITIVE_KEY_PATTERN.match?(k)
  end

  def format_event(event, metadata)
    ([event] + format_metadata(metadata)).join(" ")
  end

  def format_metadata(metadata)
    metadata.compact.map do |key, value|
      "#{key}=#{sanitize_value(key, value)}"
    end
  end

  def sanitize_value(key, value)
    return "[FILTERED]" if sensitive_key?(key)

    compact_message(
      case value
      when String
        value.inspect
      else
        summarize(value).inspect
      end
    )
  end

  def compact_message(message)
    message.to_s.gsub(/\s+/, " ").strip.truncate(MAX_VALUE_CHARS)
  end

  def redact_anthropic_key(text)
    text.to_s.gsub(ANTHROPIC_KEY_REGEXP, "[FILTERED]")
  end
end
