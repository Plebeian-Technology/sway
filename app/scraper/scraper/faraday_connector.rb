# typed: true
# frozen_string_literal: true

# https://medium.com/@zozulyak.nick/ruby-class-pattern-to-work-with-api-requests-with-built-in-async-approach-bf0713a7dc96

# require 'faraday'
# require 'faraday_curl'
# require 'concurrent'

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

      # creating a Promise for async approach
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
      # override/implement the real request in Child
    end

    def do_process
      # implement additional response decorations in Child
      request.value!
    end

    def url
      Kernel.raise NotImplementedError.new(
                     "url must be implemented by a child of this module",
                   )
    end

    def auth
      # must be added in Child or use nil, if API has no Authorization
      Kernel.raise NotImplementedError.new(
                     "auth must be implemented by a child of this module",
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
          faraday.headers =
            faraday.headers.merge(additional_headers) if additional_headers
          faraday.options.timeout = timeout
          faraday.response(:logger)
          # faraday.request :curl, Logger.new($stdout), :info
          faraday.adapter Faraday.default_adapter
        end
    end

    def handle_request(&)
      response = handle_errors(&)
      parse_response(response)
    end

    # just an easier way to handle HTTP errors
    def handle_errors
      response = yield
      e =
        if [502, 504].include?(response.status)
          TimeoutError.new(response)
        elsif [500, 503].include?(response.status)
          ServerError.new(response)
        elsif [400, 401, 404, 422].include?(response.status)
          ClientError.new(response)
        end
      return response unless e

      Kernel.raise e
    end

    def parse_response(response)
      return {} unless response.body

      return JSON.parse(response.body) if json_content?

      # return Hash.from_xml(response.body) if xml_content?

      response.body
    rescue JSON::ParserError
      {}
    end

    def json_content?
      content_type == "application/json"
    end

    def xml_content?
      content_type == "text/xml"
    end
  end
end
