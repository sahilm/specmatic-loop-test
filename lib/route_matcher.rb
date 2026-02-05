# frozen_string_literal: true

require "set"
require_relative "openapi_spec"

class RouteMatcher
  attr_reader :spec

  HTTP_METHODS = %w[get post put patch delete].freeze

  def initialize(spec_path)
    @spec = OpenApiSpec.new(spec_path)
    @routes = build_routes
  end

  def match(method, url)
    path = URI.parse(url).path
    @routes.keys.find do |spec_method, path_pattern|
      method == spec_method && pattern_to_regex(path_pattern).match?(path)
    end
  end

  def all_routes
    @routes.keys.to_set
  end

  def operation_for(route_key)
    @routes[route_key]
  end

  private

  def build_routes
    routes = {}
    @spec.paths.each do |path_pattern, path_item|
      HTTP_METHODS.each do |method|
        operation = path_item.public_send(method)
        routes[[method.upcase, path_pattern]] = operation if operation
      end
    end
    routes
  end

  def pattern_to_regex(pattern)
    Regexp.new("^" + pattern.gsub(/\{[^}]+\}/, "[^/]+") + "$")
  end
end
