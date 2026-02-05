# frozen_string_literal: true

require_relative "spec_helper"
require "open3"
require "json"

RSpec.describe "Specmatic" do

  before(:all) do
    Open3.capture2e("docker-compose down --remove-orphans")
  end

  it "runs the service stub and tests pass" do
    output, status = Open3.capture2e("docker-compose up --exit-code-from test")
    expect(status.success?).to be(true), -> { "docker-compose failed:\n#{output}" }
  end

  it "generates the correct request/response pairs" do
    http_captured_lines, status = Open3.capture2e("docker-compose logs mitm --no-color --no-log-prefix")
    expect(status.success?).to be(true), -> { "docker-compose failed:\n#{http_captured_lines}" }

    http_captured_lines.each_line do |entry|
      method, url, request_headers, request_body, status, response_headers, response_body = JSON.parse(entry)

      # ------------------------
      # HEAD /
      # ------------------------
      if method == "HEAD"
        # request headers
        expect(request_headers["User-Agent"]).to match(/^Java\//)
        expect(request_headers["Host"]).to eq("host.docker.internal:9000")
        expect(request_headers["Accept"]).to eq("text/html, image/gif, image/jpeg, */*; q=0.2")
        expect(request_headers["Connection"]).to eq("keep-alive")

        # response headers
        expect(response_headers["Vary"]).to eq("Origin")
        expect(response_headers["X-Specmatic-Result"]).to eq("failure")
        expect(response_headers["X-Specmatic-Empty"]).to eq("true")
        expect(response_headers["Content-Length"]).to eq("66")
        expect(response_headers["Content-Type"]).to eq("text/plain")
        expect(response_headers["Connection"]).to eq("keep-alive")

        expect(status).to eq(400)
        expect(response_body.to_s).to eq("")
        next
      end

      # ------------------------
      # GET /swagger/v1/swagger.yaml
      # ------------------------
      if method == "GET" && url.include?("/swagger/v1/swagger.yaml")
        # request headers
        expect(request_headers["Host"]).to eq("host.docker.internal:9000")
        expect(request_headers["Accept-Charset"]).to eq("UTF-8")
        expect(request_headers["Accept"]).to eq("*/*")
        expect(request_headers["User-Agent"]).to eq("Ktor client")
        expect(request_headers["Content-Length"]).to eq("0")
        expect(request_headers["Content-Type"]).to eq("text/plain")
        expect(request_headers["Connection"]).to eq("Keep-Alive")

        # response headers
        expect(response_headers["Vary"]).to eq("Origin")
        expect(response_headers["X-Specmatic-Result"]).to eq("failure")
        expect(response_headers["X-Specmatic-Empty"]).to eq("true")
        expect(response_headers["Content-Length"]).to eq("88")
        expect(response_headers["Content-Type"]).to eq("text/plain")
        expect(response_headers["Connection"]).to eq("keep-alive")

        expect(status).to eq(400)
        expect(response_body).to include("No matching REST stub")
        next
      end

      # ------------------------
      # POST /widgets
      # ------------------------
      if method == "POST" && url.end_with?("/widgets")
        expect(status).to eq(201)

        # request headers
        expect(request_headers["Specmatic-Response-Code"]).to eq("201")
        expect(request_headers["Host"]).to eq("host.docker.internal:9000")
        expect(request_headers["Accept-Charset"]).to eq("UTF-8")
        expect(request_headers["Accept"]).to eq("*/*")
        expect(request_headers["User-Agent"]).to eq("Ktor client")
        expect(request_headers["Content-Length"]).to eq(request_body.bytesize.to_s)
        expect(request_headers["Content-Type"]).to eq("application/json")
        expect(request_headers["Connection"]).to eq("Keep-Alive")

        # request body
        req = JSON.parse(request_body)
        expect(req.keys).to contain_exactly("name", "type")

        expect(req["name"]).to be_a(String)
        expect(req["name"].length).to be_between(1, 100)

        expect(%w[mechanical hydraulic]).to include(req["type"])

        # response headers
        expect(response_headers["Vary"]).to eq("Origin")
        expect(response_headers["X-Specmatic-Result"]).to eq("success")
        expect(response_headers["X-Specmatic-Type"]).to eq("random")
        expect(response_headers["Content-Length"]).to eq(response_body.bytesize.to_s)
        expect(response_headers["Content-Type"]).to eq("application/json")
        expect(response_headers["Connection"]).to eq("keep-alive")

        # response body
        res = JSON.parse(response_body)
        expect(res.keys).to eq(["id"])
        expect(res["id"]).to be_a(Integer)

        next
      end

      # ------------------------
      # GET /widgets/{id}
      # ------------------------
      if method == "GET" && url.match?(%r{/widgets/\d+$})
        expect(status).to eq(200)

        # request headers
        expect(request_headers["Specmatic-Response-Code"]).to eq("200")
        expect(request_headers["Host"]).to eq("host.docker.internal:9000")
        expect(request_headers["Accept-Charset"]).to eq("UTF-8")
        expect(request_headers["Accept"]).to eq("*/*")
        expect(request_headers["User-Agent"]).to eq("Ktor client")
        expect(request_headers["Connection"]).to eq("Keep-Alive")

        # response headers
        expect(response_headers["Vary"]).to eq("Origin")
        expect(response_headers["X-Specmatic-Result"]).to eq("success")
        expect(response_headers["X-Specmatic-Type"]).to eq("random")
        expect(response_headers["Content-Length"]).to eq(response_body.bytesize.to_s)
        expect(response_headers["Content-Type"]).to eq("application/json")
        expect(response_headers["Connection"]).to eq("keep-alive")

        # response body
        res = JSON.parse(response_body)
        expect(res.keys).to contain_exactly("id", "name", "type")

        expect(res["id"]).to be_a(Integer)
        expect(res["name"]).to be_a(String)
        expect(res["name"].length).to be_between(1, 100)
        expect(%w[mechanical hydraulic]).to include(res["type"])

        next
      end

      # ------------------------
      # Anything else is a failure
      # ------------------------
      raise "Unhandled HTTP entry: #{entry.inspect}"
    end

  end
end
