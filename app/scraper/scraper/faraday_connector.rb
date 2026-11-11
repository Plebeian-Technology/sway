# frozen_string_literal: true

module Scraper
  module FaradayConnector
    class ServerError < RuntimeError
      attr_reader :response

      def initialize(response)
        @response = response
        super
      end
    end

    class TimeoutError < RuntimeError
    end

    class ClientError < RuntimeError
    end

    def request
      return @request if defined?(@request)

      @request = Concurrent::Promises.future { do_request }
    end

    def process
      return @process if defined?(@process)

      request
      @process = do_process
    end

    def as_json(_options = {})
      process
    end

    protected

    def do_request
    end

    def do_process
      request.value!
    end

    def url
      Kernel.raise NotImplementedError.new(
                     "url must be implemented by a child of this module"
                   )
    end

    def auth
      Kernel.raise NotImplementedError.new(
                     "auth must be implemented by a child of this module"
                   )
    end

    def additional_headers
      {}
    end

    def content_type
      "application/json"
    end

    def request_type
      :url_encoded
    end

    def get(path, params = {})
      handle_request { connection.get(path, params) }
    end

    def post(path, body = {})
      formatted_body = json_content? ? body.to_json : body
      handle_request { connection.post(path, formatted_body) }
    end

    def delete(path, params = {})
      handle_request { connection.delete(path, params) }
    end

    def put(path, body = {})
      formatted_body = json_content? ? body.to_json : body
      handle_request { connection.put(path, formatted_body) }
    end

    def timeout
      5
    end

    def connection
      u = url
      if auth&.dig(:url)
        u =
          if u.include? "?"
            "#{u}&#{auth.dig(:url, :key)}=#{auth.dig(:url, :value)}"
          else
            "#{u}?#{auth.dig(:url, :key)}=#{auth.dig(:url, :value)}"
          end
      end

      @connection ||=
        Faraday.new(url: u) do |faraday|
          faraday.request request_type
          faraday.headers["Authorization"] = auth[:header] if auth&.dig(:header)
          faraday.headers["Content-Type"] = content_type
          faraday.headers.merge!(additional_headers) if additional_headers
          faraday.options.timeout = timeout
          faraday.response(:logger)
          faraday.adapter Faraday.default_adapter
        end
    end

    def handle_request(&)
      response = handle_errors(&)
      parse_response(response)
    end

    def handle_errors
      response = yield
      e =
        if [502, 504].include?(response.status)
          TimeoutError.new(response)
        elsif (500..599).cover?(response.status)
          ServerError.new(response)
        elsif (300..499).cover?(response.status)
          ClientError.new(response)
        end
      return response unless e

      Kernel.raise e
    end

    def parse_response(response)
      return {} unless response.body

      return JSON.parse(response.body) if json_content?

      response.body
    rescue JSON::ParserError
      {}
    end

    def json_content?
      content_type == "application/json"
    end
  end
end
