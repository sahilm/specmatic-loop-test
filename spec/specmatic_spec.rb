# frozen_string_literal: true

require_relative "spec_helper"
require_relative "support/docker_compose"
require_relative "../lib/route_matcher"
require_relative "../lib/schema_validator"
require_relative "../lib/http_entry"
require "json"

RSpec.describe "Specmatic" do
  SERVICES = [
    { compose_file: "docker-compose.service1.yaml", spec_file: "service1.yaml" },
    { compose_file: "docker-compose.service2.yaml", spec_file: "service2.yaml" }
  ].freeze

  SERVICES.each do |service|
    context "with #{service[:spec_file]}" do
      before(:all) do
        @docker = DockerCompose::Runner.new(service[:compose_file])
        @docker.run

        spec_path = File.expand_path("../#{service[:spec_file]}", __dir__)
        @route_matcher = RouteMatcher.new(spec_path)
        @schema_validator = SchemaValidator.new(@route_matcher.spec)
        @entries = @docker.http_output.each_line.map { |line| HttpEntry.parse(line, @route_matcher) }
      end

      after(:all) do
        @docker.down
      end

      it "runs the service stub and tests pass" do
        expect(@docker.test_succeeded?).to be(true), -> { "docker-compose failed:\n#{@docker.test_output}" }
      end

      it "exercises all routes defined in the OpenAPI spec" do
        expect(@docker.http_logs_succeeded?).to be(true)

        hit_routes = @entries.select(&:matched?).map(&:matched_route).to_set
        unmatched = @entries.reject(&:matched?)

        if unmatched.any?
          warn "\nWARNING: Routes not in OpenAPI spec (#{service[:spec_file]}) were hit:"
          unmatched.each { |e| warn "  - #{e}" }
        end

        uncovered = @route_matcher.all_routes - hit_routes
        expect(uncovered).to be_empty, "Routes not exercised: #{uncovered.to_a}"
      end

      it "sends valid request headers" do
        entries_with_request_body.each do |entry|
          operation = @route_matcher.operation_for(entry.matched_route)
          expected_types = operation.request_body&.content&.keys || []

          aggregate_failures entry.to_s do
            expect(expected_types).to include(entry.request_content_type),
              "Unexpected Content-Type: #{entry.request_content_type}"
            expect(entry.request_headers["Content-Length"]).to eq(entry.request_body.bytesize.to_s),
              "Content-Length mismatch"
          end
        end
      end

      it "sends valid request bodies" do
        entries_with_request_body.each do |entry|
          operation = @route_matcher.operation_for(entry.matched_route)
          media_type = operation.request_body&.content&.[](entry.request_content_type)
          next unless media_type&.schema

          pointer = @schema_validator.request_schema_pointer(
            entry.path_pattern, entry.method, entry.request_content_type
          )
          errors = @schema_validator.validate(pointer, JSON.parse(entry.request_body))

          expect(errors).to be_empty, "#{entry}: #{errors}"
        end
      end

      it "receives valid response headers" do
        entries_with_response_body.each do |entry|
          operation = @route_matcher.operation_for(entry.matched_route)
          response_def = operation.responses[entry.status_code.to_s]
          expected_types = response_def&.content&.keys || []

          aggregate_failures entry.to_s do
            expect(expected_types).to include(entry.response_content_type),
              "Unexpected Content-Type: #{entry.response_content_type}"
            expect(entry.response_headers["Content-Length"]).to eq(entry.response_body.bytesize.to_s),
              "Content-Length mismatch"
          end
        end
      end

      it "receives valid response bodies" do
        entries_with_response_body.each do |entry|
          operation = @route_matcher.operation_for(entry.matched_route)
          response_def = operation.responses[entry.status_code.to_s]
          media_type = response_def&.content&.[](entry.response_content_type)
          next unless media_type&.schema

          pointer = @schema_validator.response_schema_pointer(
            entry.path_pattern, entry.method, entry.status_code, entry.response_content_type
          )
          errors = @schema_validator.validate(pointer, JSON.parse(entry.response_body))

          expect(errors).to be_empty, "#{entry}: #{errors}"
        end
      end

      private

      def entries_with_request_body
        @entries.select { |e| e.matched? && e.has_request_body? }
      end

      def entries_with_response_body
        @entries.select { |e| e.matched? && e.has_response_body? }
      end
    end
  end
end
