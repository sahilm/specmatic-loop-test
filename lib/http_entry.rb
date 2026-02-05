# frozen_string_literal: true

class HttpEntry
  METHODS_WITH_REQUEST_BODY = %w[POST PUT PATCH].freeze

  attr_reader :method, :url, :request_headers, :request_body,
              :status_code, :response_headers, :response_body, :matched_route

  def initialize(method:, url:, request_headers:, request_body:,
                 status_code:, response_headers:, response_body:, matched_route:)
    @method = method
    @url = url
    @request_headers = request_headers
    @request_body = request_body
    @status_code = status_code
    @response_headers = response_headers
    @response_body = response_body
    @matched_route = matched_route
  end

  def self.parse(line, route_matcher)
    method, url, req_headers, req_body, status, res_headers, res_body = JSON.parse(line)
    new(
      method: method,
      url: url,
      request_headers: req_headers,
      request_body: req_body,
      status_code: status,
      response_headers: res_headers,
      response_body: res_body,
      matched_route: route_matcher.match(method, url)
    )
  end

  def matched?
    !matched_route.nil?
  end

  def path_pattern
    matched_route&.[](1)
  end

  def has_request_body?
    METHODS_WITH_REQUEST_BODY.include?(method) && request_body && !request_body.empty?
  end

  def has_response_body?
    response_body && !response_body.empty?
  end

  def request_content_type
    request_headers["Content-Type"]&.split(";")&.first
  end

  def response_content_type
    response_headers["Content-Type"]&.split(";")&.first
  end

  def to_s
    "#{method} #{url}"
  end
end
