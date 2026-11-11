# frozen_string_literal: true

# @lat: [[local-error-reporting-design#Why SwayLocalErrorDsn refuses rather than warns]]
module SwayLocalErrorDsn
  LOCAL_HOSTS = %w[
    localhost
    127.0.0.1
    ::1
    host.docker.internal
    rustrak
  ].freeze

  module_function

  def local?(dsn)
    return false if dsn.nil? || dsn.to_s.strip.empty?

    host = URI.parse(dsn.to_s.strip).host
    return false if host.nil?

    LOCAL_HOSTS.include?(host.downcase.delete_prefix("[").delete_suffix("]"))
  rescue URI::InvalidURIError
    false
  end

  # @lat: [[local-error-reporting-design#Why SwayLocalErrorDsn refuses rather than warns]]
  def browser_origin(dsn)
    return nil unless local?(dsn)

    uri = URI.parse(dsn.to_s.strip)
    return nil if uri.scheme.nil? || uri.host.nil?

    default_port = (uri.scheme == "https") ? 443 : 80
    return "#{uri.scheme}://#{uri.host}" if uri.port.nil? || uri.port == default_port

    "#{uri.scheme}://#{uri.host}:#{uri.port}"
  rescue URI::InvalidURIError
    nil
  end
end
