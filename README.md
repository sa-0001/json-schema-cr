# json-schema

JSON Schema validator library, corresponding to the [OpenAPI/Swagger](https://swagger.io/docs/specification/data-models/data-types/) variant of JSON Schema.

Implemented keywords:
* any type
  * const
  * (TODO) default
  * enum
  * nullable
  * type
* array
  * items
  * (TODO) additionalItems
  * minItems
  * maxItems
  * uniqueItems
* number
  * minimum
  * exclusiveMinimum
  * maximum
  * exclusiveMaximum
  * multipleOf
* object
  * properties
  * (TODO) additionalProperties
  * minProperties
  * maxProperties
  * (TODO) required
* strings
  * (TODO) format
  * minLength
  * maxLength
  * (TODO) pattern
* sub-schemas
  * allOf
  * anyOf
  * oneOf
  * not

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  json-schema:
    github: sa-0001/json-schema-cr
```

## Usage & Examples

```crystal
require "json-schema"

schema = JsonSchema.new %({
	"type": "object",
	"properties": {
		"name": {
			"type" "string"
		},
		"age": {
			"type" "integer"
		}
	}
})

result = schema.validate %({
	"name": "Johnny",
	"age": "30"	
})

pp result.valid, result.errors
```
