# frozen_string_literal: true

class SchemaValidator
  def initialize(spec)
    @spec = spec
  end

  def validate(json_pointer, data)
    schema = @spec.schema_for(json_pointer)
    schema.validate(data).map { |e| e["error"] }
  end
end
