# frozen_string_literal: true

class SchemaValidator
  def initialize(spec)
    @spec = spec
  end

  def validate(json_pointer, data)
    schema = @spec.schema_for(json_pointer)
    schema.validate(data).map { |e| e["error"] }
  end

  def request_schema_pointer(path_pattern, method, content_type)
    escaped_path = escape_json_pointer(path_pattern)
    escaped_content_type = escape_json_pointer(content_type)
    "#/paths/#{escaped_path}/#{method.downcase}/requestBody/content/#{escaped_content_type}/schema"
  end

  def response_schema_pointer(path_pattern, method, status_code, content_type)
    escaped_path = escape_json_pointer(path_pattern)
    escaped_content_type = escape_json_pointer(content_type)
    "#/paths/#{escaped_path}/#{method.downcase}/responses/#{status_code}/content/#{escaped_content_type}/schema"
  end

  private

  def escape_json_pointer(str)
    escaped = str.gsub("~", "~0").gsub("/", "~1")
    URI::DEFAULT_PARSER.escape(escaped, /[{}]/)
  end
end
