# frozen_string_literal: true

require "json"

# @lat: [[sway-error-scrubber-design#Why the scrubber exists]]
module SwayErrorScrubber
  # @lat: [[sway-error-scrubber-design#Why the rules table has three readers]]
  RULES_PATH = "app/frontend/sway_constants/errorScrubRules.json"

  RULES = JSON.parse(File.read(File.expand_path("../#{RULES_PATH}", File.dirname(__FILE__)))).freeze

  REDACTIONS = RULES.fetch("redactions").map { |rule|
    [Regexp.new(rule.fetch("pattern")), rule.fetch("label")]
  }.freeze

  MAX_STRING_LENGTH = RULES.fetch("maxStringLength")
  MAX_DEPTH = RULES.fetch("maxDepth")

  PRESERVED_KEYS = RULES.fetch("preservedKeys").freeze
  DROPPED_KEYS = RULES.fetch("droppedKeys").freeze

  module_function

  # @lat: [[sway-error-scrubber-design#Why scrubString (mobile) caps a huge value before redacting, not after]]
  def scrub_text(value)
    text = value.to_s
    if text.length > MAX_STRING_LENGTH
      text = "#{text[0, MAX_STRING_LENGTH]}…[truncated #{text.length - MAX_STRING_LENGTH} chars]"
    end

    REDACTIONS.each { |pattern, label| text = text.gsub(pattern, label) }
    text
  end

  def deep_scrub(value, depth = 0)
    return "[FILTERED_TOO_DEEP]" if depth >= MAX_DEPTH

    case value
    when String
      scrub_text(value)
    when Symbol
      scrub_text(value.to_s).to_sym
    when Array
      value.map { |item| deep_scrub(item, depth + 1) }
    when Hash
      value.each_with_object({}) do |(key, item), scrubbed|
        name = key.to_s.downcase
        scrubbed[key] = if DROPPED_KEYS.include?(name)
          dropped(item)
        elsif PRESERVED_KEYS.include?(name)
          item
        else
          deep_scrub(item, depth + 1)
        end
      end
    else
      value
    end
  end

  # @lat: [[sway-error-scrubber-design#Why dropped() preserves type in scrub_error_event.ts]]
  def dropped(value)
    case value
    when Array then []
    when Hash then {}
    else "[FILTERED]"
    end
  end

  def call(event, _hint = nil)
    scrub_exception(event)
    scrub_request(event)
    scrub_breadcrumbs(event)

    event.message = scrub_text(event.message) if event.respond_to?(:message) && event.message.is_a?(String)

    remove_empty_fingerprint(event)

    event.extra = deep_scrub(event.extra) if event.respond_to?(:extra) && event.extra.is_a?(Hash)
    event.tags = deep_scrub(event.tags) if event.respond_to?(:tags) && event.tags.is_a?(Hash)
    event.user = deep_scrub(event.user) if event.respond_to?(:user) && event.user.is_a?(Hash)
    event.transaction = scrub_text(event.transaction) if event.respond_to?(:transaction) && event.transaction.is_a?(String)

    event
  end

  # @lat: [[error-scrubber-empty-fingerprint-bug#Why scrubErrorEvent (the web beforeSend hook) also removes it]]
  def remove_empty_fingerprint(event)
    return unless event.respond_to?(:fingerprint) && event.respond_to?(:fingerprint=)

    event.fingerprint = nil if event.fingerprint == []
  end

  def scrub_exception(event)
    return unless event.respond_to?(:exception)

    exception = event.exception
    return if exception.nil? || !exception.respond_to?(:values)

    exception.values.each do |single|
      single.value = scrub_text(single.value) if single.respond_to?(:value=) && single.value.is_a?(String)
    end
  end

  # @lat: [[sway-error-scrubber-design#Why breadcrumbs need their own scrub]]
  def scrub_breadcrumbs(event)
    return unless event.respond_to?(:breadcrumbs)

    buffer = event.breadcrumbs
    return if buffer.nil? || !buffer.respond_to?(:buffer)

    buffer.buffer.each do |crumb|
      next if crumb.nil?

      crumb.message = scrub_text(crumb.message) if crumb.respond_to?(:message=) && crumb.message.is_a?(String)
      crumb.data = deep_scrub(crumb.data) if crumb.respond_to?(:data=) && !crumb.data.nil?
    end
  end

  def scrub_request(event)
    return unless event.respond_to?(:request)

    request = event.request
    return if request.nil?

    request.url = scrub_text(request.url) if request.respond_to?(:url=) && request.url.is_a?(String)
    request.query_string = scrub_text(request.query_string) if request.respond_to?(:query_string=) && request.query_string.is_a?(String)
    request.data = deep_scrub(request.data) if request.respond_to?(:data=) && !request.data.nil?
    request.cookies = nil if request.respond_to?(:cookies=)
    request.headers = {} if request.respond_to?(:headers=)
    request.env = {} if request.respond_to?(:env=)
  end
end
