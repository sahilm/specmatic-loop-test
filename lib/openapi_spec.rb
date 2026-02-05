# frozen_string_literal: true

require "openapi3_parser"
require "json_schemer"
require "yaml"

class OpenApiSpec
  attr_reader :document

  def initialize(spec_path)
    spec_data = YAML.load_file(spec_path)
    @document = Openapi3Parser.load(spec_data)
    raise "Invalid OpenAPI spec: #{@document.errors.map(&:message).join(', ')}" unless @document.valid?

    @schemer = JSONSchemer.openapi(spec_data)
  end

  def paths
    @document.paths
  end

  def schema_for(json_pointer)
    @schemer.ref(json_pointer)
  end
end
