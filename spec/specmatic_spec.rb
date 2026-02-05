# frozen_string_literal: true

require_relative "spec_helper"
require_relative "../lib/route_matcher"
require_relative "../lib/schema_validator"
require "open3"
require "json"

RSpec.describe "Specmatic" do
  SERVICES = [
    { compose_file: "docker-compose.service1.yaml", spec_file: "service1.yaml" },
    { compose_file: "docker-compose.service2.yaml", spec_file: "service2.yaml" }
  ].freeze

  def self.escape_json_pointer(str)
    escaped = str.gsub("~", "~0").gsub("/", "~1")
    URI::DEFAULT_PARSER.escape(escaped, /[{}]/)
  end

  def self.request_schema_pointer(path_pattern, method, content_type)
    escaped_path = escape_json_pointer(path_pattern)
    escaped_content_type = escape_json_pointer(content_type)
    "#/paths/#{escaped_path}/#{method.downcase}/requestBody/content/#{escaped_content_type}/schema"
  end

  def self.response_schema_pointer(path_pattern, method, status_code, content_type)
    escaped_path = escape_json_pointer(path_pattern)
    escaped_content_type = escape_json_pointer(content_type)
    "#/paths/#{escaped_path}/#{method.downcase}/responses/#{status_code}/content/#{escaped_content_type}/schema"
  end

  SERVICES.each do |service|
    context "with #{service[:spec_file]}" do
      let(:compose_file) { service[:compose_file] }
      let(:spec_file) { service[:spec_file] }

      before(:all) do
        compose = service[:compose_file]
        spec = service[:spec_file]

        Open3.capture2e("docker-compose -f #{compose} down --remove-orphans")
        @test_output, @test_status = Open3.capture2e("docker-compose -f #{compose} up --exit-code-from test")
        @http_output, @http_status = Open3.capture2e("docker-compose -f #{compose} logs mitm --no-color --no-log-prefix")

        spec_path = File.expand_path("../#{spec}", __dir__)
        @route_matcher = RouteMatcher.new(spec_path)
        @schema_validator = SchemaValidator.new(@route_matcher.spec)
        @entries = parse_entries(@http_output, @route_matcher)
      end

      after(:all) do
        Open3.capture2e("docker-compose -f #{service[:compose_file]} down --remove-orphans")
      end

      def parse_entries(output, route_matcher)
        output.each_line.map do |line|
          method, url, req_headers, req_body, status, res_headers, res_body = JSON.parse(line)
          {
            method: method,
            url: url,
            request_headers: req_headers,
            request_body: req_body,
            status_code: status,
            response_headers: res_headers,
            response_body: res_body,
            matched_key: route_matcher.match(method, url)
          }
        end
      end

      def matched_entries
        @entries.select { |e| e[:matched_key] }
      end

      def request_entries
        matched_entries.select do |e|
          %w[POST PUT PATCH].include?(e[:method]) && e[:request_body] && !e[:request_body].empty?
        end
      end

      def response_entries
        matched_entries.select { |e| e[:response_body] && !e[:response_body].empty? }
      end

      it "runs the service stub and tests pass" do
        expect(@test_status.success?).to be(true), -> { "docker-compose failed:\n#{@test_output}" }
      end

      it "exercises all routes defined in the OpenAPI spec" do
        expect(@http_status.success?).to be(true)

        hit_routes = matched_entries.map { |e| e[:matched_key] }.to_set
        unknown_routes = @entries.reject { |e| e[:matched_key] }.map { |e| [e[:method], e[:url]] }.uniq

        if unknown_routes.any?
          warn "\nWARNING: Routes not in OpenAPI spec (#{spec_file}) were hit:"
          unknown_routes.each { |m, u| warn "  - #{m} #{u}" }
        end

        uncovered = @route_matcher.all_routes - hit_routes
        expect(uncovered).to be_empty, "Routes not exercised: #{uncovered.to_a}"
      end

      it "sends valid request headers" do
        request_entries.each do |entry|
          operation = @route_matcher.operation_for(entry[:matched_key])
          content_type = entry[:request_headers]["Content-Type"]&.split(";")&.first
          expected_types = operation.request_body&.content&.keys || []

          aggregate_failures "#{entry[:method]} #{entry[:url]}" do
            expect(expected_types).to include(content_type), "Unexpected Content-Type: #{content_type}"
            expect(entry[:request_headers]["Content-Length"]).to eq(entry[:request_body].bytesize.to_s),
              "Content-Length mismatch"
          end
        end
      end

      it "sends valid request bodies" do
        request_entries.each do |entry|
          operation = @route_matcher.operation_for(entry[:matched_key])
          content_type = entry[:request_headers]["Content-Type"]&.split(";")&.first
          media_type = operation.request_body&.content&.[](content_type)
          next unless media_type&.schema

          path_pattern = entry[:matched_key][1]
          pointer = self.class.request_schema_pointer(path_pattern, entry[:method], content_type)
          errors = @schema_validator.validate(pointer, JSON.parse(entry[:request_body]))

          expect(errors).to be_empty, "#{entry[:method]} #{entry[:url]}: #{errors}"
        end
      end

      it "receives valid response headers" do
        response_entries.each do |entry|
          operation = @route_matcher.operation_for(entry[:matched_key])
          content_type = entry[:response_headers]["Content-Type"]&.split(";")&.first
          response_def = operation.responses[entry[:status_code].to_s]
          expected_types = response_def&.content&.keys || []

          aggregate_failures "#{entry[:method]} #{entry[:url]}" do
            expect(expected_types).to include(content_type), "Unexpected Content-Type: #{content_type}"
            expect(entry[:response_headers]["Content-Length"]).to eq(entry[:response_body].bytesize.to_s),
              "Content-Length mismatch"
          end
        end
      end

      it "receives valid response bodies" do
        response_entries.each do |entry|
          operation = @route_matcher.operation_for(entry[:matched_key])
          content_type = entry[:response_headers]["Content-Type"]&.split(";")&.first
          response_def = operation.responses[entry[:status_code].to_s]
          media_type = response_def&.content&.[](content_type)
          next unless media_type&.schema

          path_pattern = entry[:matched_key][1]
          pointer = self.class.response_schema_pointer(path_pattern, entry[:method], entry[:status_code], content_type)
          errors = @schema_validator.validate(pointer, JSON.parse(entry[:response_body]))

          expect(errors).to be_empty, "#{entry[:method]} #{entry[:url]}: #{errors}"
        end
      end
    end
  end
end
