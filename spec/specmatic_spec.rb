# frozen_string_literal: true

require_relative "spec_helper"
require_relative "support/docker_compose"
require_relative "../lib/route_matcher"
require_relative "../lib/schema_validator"
require_relative "../lib/http_capture"
require "json"

RSpec.describe "Specmatic" do
  SERVICES = [
    { compose_file: "docker-compose.service1.yaml", spec_file: "service1.yaml", specmatic_version: '2.42.2' },
    { compose_file: "docker-compose.service2.yaml", spec_file: "service2.yaml", specmatic_version: '2.42.2' },
    { compose_file: "docker-compose.service3.yaml", spec_file: "service3.yaml", specmatic_version: '2.42.2' },
    { compose_file: "docker-compose.service3.yaml", spec_file: "service3.yaml", specmatic_version: '2.39.0' },
  ].freeze

  SERVICES.each do |service|
    context "with #{service[:spec_file]} and specmatic version #{service[:specmatic_version]}" do
      before(:all) do
        @docker = DockerCompose::Runner.new(service[:compose_file], service[:specmatic_version])
        @docker.run

        spec_path = File.expand_path("../#{service[:spec_file]}", __dir__)
        @route_matcher = RouteMatcher.new(spec_path)
        @schema_validator = SchemaValidator.new(@route_matcher.spec)
        @http_captures = @docker.http_capture.each_line.map { |line| HttpCapture.parse(line, @route_matcher) }
      end

      after(:all) do
        @docker.down
      end

      it "runs the service stub and tests pass" do
        expect(@docker.test_succeeded?).to be(true), -> { "docker-compose failed:\n#{@docker.test_output}" }
      end

      it "exercises all routes defined in the OpenAPI spec" do
        expect(@docker.http_capture_succeeded?).to be(true)

        hit_routes = @http_captures.select(&:matched?).map(&:matched_route).to_set
        unmatched = @http_captures.reject(&:matched?)

        puts "\nMatched routes for #{service[:spec_file]}:"
        hit_routes.each { |r| puts "  - #{r}" }

        if unmatched.any?
          warn "\nWARNING: Routes not in OpenAPI spec (#{service[:spec_file]}) were hit:"
          unmatched.each { |e| warn "  - #{e}" }
        end

        uncovered = @route_matcher.all_routes - hit_routes
        expect(uncovered).to be_empty, "Routes not exercised: #{uncovered.to_a}"
      end

      it "sends valid request headers" do
        http_captures_with_request_body.each do |http_capture|
          operation = @route_matcher.operation_for(http_capture.matched_route)
          expected_types = operation.request_body&.content&.keys || []

          aggregate_failures http_capture.to_s do
            expect(expected_types).to include(http_capture.request_content_type),
                                      "Unexpected Content-Type: #{http_capture.request_content_type}"
            expect(http_capture.request_headers["Content-Length"]).to eq(http_capture.request_body.bytesize.to_s),
                                                                      "Content-Length mismatch"
          end
        end
      end

      it "sends valid request bodies" do
        http_captures_with_request_body.each do |http_capture|
          body = begin
            JSON.parse(http_capture.request_body)
          rescue JSON::ParserError => e
            fail "#{http_capture}: Invalid JSON in request body: #{e.message}"
          end

          errors = @schema_validator.validate_request(
            path_pattern: http_capture.path_pattern,
            content_type: http_capture.request_content_type,
            method: http_capture.method,
            body: body
          )
          expect(errors).to be_empty, "#{http_capture}: #{errors}"
        end
      end

      it "receives valid response headers" do
        http_captures_with_response_body.each do |http_capture|
          operation = @route_matcher.operation_for(http_capture.matched_route)
          response_def = operation.responses[http_capture.status_code.to_s]

          aggregate_failures http_capture.to_s do
            expect(response_def).not_to be_nil,
                                        "Status code #{http_capture.status_code} not defined in OpenAPI spec"

            expected_types = response_def&.content&.keys || []
            expect(expected_types).to include(http_capture.response_content_type),
                                      "Unexpected Content-Type: #{http_capture.response_content_type}"
            expect(http_capture.response_headers["Content-Length"]).to eq(http_capture.response_body.bytesize.to_s),
                                                                       "Content-Length mismatch"
          end
        end
      end

      it "receives valid response bodies" do
        http_captures_with_response_body.each do |http_capture|
          body = begin
            JSON.parse(http_capture.response_body)
          rescue JSON::ParserError => e
            fail "#{http_capture}: Invalid JSON in response body: #{e.message}"
          end

          errors = @schema_validator.validate_response(
            path_pattern: http_capture.path_pattern,
            content_type: http_capture.response_content_type,
            method: http_capture.method,
            status_code: http_capture.status_code,
            body: body
          )
          expect(errors).to be_empty, "#{http_capture}: #{errors}"
        end
      end

      def http_captures_with_request_body
        @http_captures.select { |e| e.matched? && e.has_request_body? }
      end

      def http_captures_with_response_body
        @http_captures.select { |e| e.matched? && e.has_response_body? }
      end
    end
  end
end
