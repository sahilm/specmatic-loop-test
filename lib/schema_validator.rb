# frozen_string_literal: true

require "cgi"

class SchemaValidator
  def initialize(spec)
    @spec = spec
  end

  def validate_request(path_pattern:, content_type:, method:, body:)
    escaped_path = escape_json_pointer(path_pattern)
    escaped_content_type = escape_json_pointer(content_type)
    schema_pointer =
      "#/paths/#{escaped_path}/#{method.downcase}/requestBody/content/#{escaped_content_type}/schema"
    schema = @spec.schema_for(schema_pointer)

    schema.validate(body).map { |e| e["error"] }
  end

  def validate_response(path_pattern:, content_type:, method:, status_code:, body:)
    escaped_path = escape_json_pointer(path_pattern)
    escaped_content_type = escape_json_pointer(content_type)
    schema_pointer =
      "#/paths/#{escaped_path}/#{method.downcase}/responses/#{status_code}/content/#{escaped_content_type}/schema"
    schema = @spec.schema_for(schema_pointer)

    schema.validate(body).map { |e| e["error"] }
  end

  private

  def escape_json_pointer(str)
    escaped = str.gsub("~", "~0").gsub("/", "~1")
    escaped.gsub(/[{}]/) { |c| CGI.escape(c) }
  end
end
