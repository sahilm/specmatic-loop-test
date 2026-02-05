# frozen_string_literal: true

require "open3"

module DockerCompose
  class Runner
    attr_reader :compose_file, :test_output, :test_status, :http_output, :http_status

    def initialize(compose_file)
      @compose_file = compose_file
    end

    def run
      down
      @test_output, @test_status = Open3.capture2e("docker-compose -f #{compose_file} up --exit-code-from test")
      @http_output, @http_status = Open3.capture2e("docker-compose -f #{compose_file} logs mitm --no-color --no-log-prefix")
    end

    def down
      Open3.capture2e("docker-compose -f #{compose_file} down --remove-orphans")
    end

    def test_succeeded?
      test_status&.success?
    end

    def http_logs_succeeded?
      http_status&.success?
    end
  end
end
