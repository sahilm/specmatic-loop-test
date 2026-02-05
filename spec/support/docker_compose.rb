# frozen_string_literal: true

require "open3"
require "shellwords"

module DockerCompose
  class Runner
    attr_reader :http_capture, :test_output

    def initialize(compose_file)
      @compose_file = compose_file
    end

    def run
      down
      escaped_file = Shellwords.shellescape(compose_file)
      @test_output, @test_status = Open3.capture2e("docker-compose -f #{escaped_file} up --exit-code-from test")
      @http_capture, @http_capture_status = Open3.capture2e("docker-compose -f #{escaped_file} logs mitm --no-color --no-log-prefix")
    end

    def down
      escaped_file = Shellwords.shellescape(compose_file)
      Open3.capture2e("docker-compose -f #{escaped_file} down --remove-orphans")
    end

    def test_succeeded?
      test_status&.success?
    end

    def http_capture_succeeded?
      http_capture_status&.success?
    end

    private

    attr_reader :compose_file, :test_status, :http_capture_status
  end
end
