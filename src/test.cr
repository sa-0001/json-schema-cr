#!/usr/bin/env crystal

require "tap"

require "./json-schema"

##======================================================================================================================

Tap.test "json-schema" do |t|
	
	t.test "validate" do |t|
		schema = JSON.parse %({
			"type": "object",
			"properties": {
				"a": {
					"type": "array",
					"items": [{
						"type": "boolean"
					},{
						"type": "number"
					}],
					"additionalItems": {
						"type": "string"
					}
				},
				"a?": {
					"type": "array",
					"nullable": true
				},
				"b": {
					"type": "boolean"
				},
				"b?": {
					"type": "boolean",
					"nullable": true
				},
				"n": {
					"type": "number"
				},
				"n?": {
					"type": "number",
					"nullable": true
				},
				"o": {
					"type": "object",
					"properties": {
						"a": {
							"type": "boolean"
						},
						"b": {
							"type": "number"
						}
					},
					"additionalProperties": {
						"c": {
							"type": "string"
						}
					}
				},
				"o?": {
					"type": "object",
					"nullable": true
				},
				"s": {
					"type": "string",
					"minLength": 1,
					"maxLength": 10
				},
				"s?": {
					"type": "string",
					"nullable": true
				},
				
				"const": {
					"type": "string",
					"const": "abc"
				},
				"enum": {
					"type": "string",
					"enum": [ "abc", "def" ]
				},
				
				"minItems": {
					"minItems": 2
				},
				"maxItems": {
					"maxItems": 2
				},
				"uniqueItems": {
					"uniqueItems": true
				},
				
				"minProperties": {
					"minProperties": 2
				},
				"maxProperties": {
					"maxProperties": 2
				},
				
				"minimum": {
					"minimum": 10
				},
				"exclusiveMinimum": {
					"minimum": 10,
					"exclusiveMinimum": true
				},
				"maximum": {
					"maximum": 10
				},
				"exclusiveMaximum": {
					"maximum": 10,
					"exclusiveMaximum": true
				},
				"multipleOf": {
					"multipleOf": 10
				},
				
				"allOf": {
					"type": "string",
					"allOf": [{
						"enum": [ "abc", "def" ]
					},{
						"minLength": 1
					},{
						"maxLength": 10
					}]
				},
				"anyOf": {
					"type": "string",
					"anyOf": [{
						"enum": [ "abc", "def" ]
					},{
						"minLength": 1
					},{
						"maxLength": 10
					}]
				},
				"oneOf": {
					"type": "string",
					"oneOf": [{
						"enum": [ "abc", "def" ]
					},{
						"enum": [ "ghi", "jkl" ]
					},{
						"enum": [ "mno", "pqr" ]
					}]
				}
			}
		})
		
		input = JSON.parse %({
			"a": [ true, 123, "abc" ],
			"a?": null,
			"b": false,
			"b?": null,
			"n": 0,
			"n?": null,
			"o": { "a": true, "b": 123, "c": "abc" },
			"o?": null,
			"s": "abc",
			"s?": null,
			
			"const": "abc",
			"enum": "abc",
			
			"minItems": [ 1, 2 ],
			"maxItems": [ 1, 2 ],
			"uniqueItems": [{ "a": 1 },{ "b": 2 }],
			
			"minProperties": { "a": 1, "b": 2 },
			"maxProperties": { "a": 1, "b": 2 },
			
			"minimum": 10,
			"exclusiveMinimum": 10.01,
			"maximum": 10,
			"exclusiveMaximum": 9.99,
			"multipleOf": 100,
			
			"allOf": "abc",
			"anyOf": "abc",
			"oneOf": "abc"
		})
		
		bad_input = %(null)
		
		# ok, pass, fail = JsonSchema.verify_schema schema
		# t.ok ok
		
		json_schema = JsonSchema.new schema
		
		result = json_schema.validate input
		t.is_true result.valid
		puts "PASS", result.asserts.join "\n"
		puts "FAIL", result.errors.join "\n"
		
		# ok, pass, fail = json_schema.validate JSON.parse bad_input
		# t.is_false ok
		# puts "PASS", pass.join "\n"
		# puts "FAIL", fail.join "\n"
	end
	
	t.test "any" do |t|
		
		t.test "const" do |t|
			schema = JsonSchema.new(%({
				"const": "abc"
			}))
			
			t.not_ok schema.validate(%(
				"def"
			)).valid
			
			t.ok schema.validate(%(
				"abc"
			)).valid
		end
		
		t.test "enum" do |t|
			schema = JsonSchema.new(%({
				"enum": [ "abc", "def" ]
			}))
			
			t.not_ok schema.validate(%(
				"ghi"
			)).valid
			
			t.ok schema.validate(%(
				"def"
			)).valid
		end
		
		t.test "nullable" do |t|
			schema = JsonSchema.new(%({
				"type": "string",
				"nullable": false
			}))
			
			t.not_ok schema.validate(%(
				null
			)).valid
			
			schema = JsonSchema.new(%({
				"type": "string",
				"nullable": true
			}))
			
			t.ok schema.validate(%(
				null
			)).valid
		end
		
		t.test "type" do |t|
			schema = JsonSchema.new(%({
				"type": "string"
			}))
			
			t.not_ok schema.validate(%(
				null
			)).valid
			
			t.ok schema.validate(%(
				"abc"
			)).valid
			
			# special case: input type "integer" is also allowed for schema type "number"
			schema = JsonSchema.new(%({
				"type": "number"
			}))
			
			t.ok schema.validate(%(
				0.0
			)).valid
			
			t.ok schema.validate(%(
				0
			)).valid
		end
	end
	
	t.test "arrays" do |t|
		
		t.test "items" do |t|
			# TODO
		end
		
		t.test "additionalItems" do |t|
			# TODO
		end
		
		t.test "minItems" do |t|
			schema = JsonSchema.new(%({
				"minItems": 2
			}))
			
			t.not_ok schema.validate(%(
				[ 1 ]
			)).valid
			
			t.ok schema.validate(%(
				[ 1, 2 ]
			)).valid
		end
		
		t.test "maxItems" do |t|
			schema = JsonSchema.new(%({
				"maxItems": 2
			}))
			
			t.not_ok schema.validate(%(
				[ 1, 2, 3 ]
			)).valid
			
			t.ok schema.validate(%(
				[ 1, 2 ]
			)).valid
		end
		
		t.test "uniqueItems" do |t|
			schema = JsonSchema.new(%({
				"uniqueItems": true
			}))
			
			t.not_ok schema.validate(%(
				[{ "a": 1 },{ "a": 1 }]
			)).valid
			
			t.ok schema.validate(%(
				[{ "a": 1 },{ "b": 2 }]
			)).valid
		end
	end
	
	t.test "numbers" do |t|
		
		t.test "minimum" do |t|
			schema = JsonSchema.new(%({
				"minimum": 10
			}))
			
			t.not_ok schema.validate(%(
				9.99
			)).valid
			
			t.ok schema.validate(%(
				10
			)).valid
		end
		
		t.test "exclusiveMinimum" do |t|
			schema = JsonSchema.new(%({
				"minimum": 10,
				"exclusiveMinimum": true
			}))
			
			t.not_ok schema.validate(%(
				10
			)).valid
			
			t.ok schema.validate(%(
				10.01
			)).valid
		end
		
		t.test "maximum" do |t|
			schema = JsonSchema.new(%({
				"maximum": 10
			}))
			
			t.not_ok schema.validate(%(
				10.01
			)).valid
			
			t.ok schema.validate(%(
				10
			)).valid
		end
		
		t.test "exclusiveMaximum" do |t|
			schema = JsonSchema.new(%({
				"maximum": 10,
				"exclusiveMaximum": true
			}))
			
			t.not_ok schema.validate(%(
				10
			)).valid
			
			t.ok schema.validate(%(
				9.99
			)).valid
		end
		
		t.test "multipleOf" do |t|
			schema = JsonSchema.new(%({
				"multipleOf": 10
			}))
			
			t.not_ok schema.validate(%(
				99
			)).valid
			
			t.ok schema.validate(%(
				100
			)).valid
		end
	end
	
	t.test "object" do |t|
		
		t.test "properties" do |t|
			# TODO
		end
		
		t.test "additionalProperties" do |t|
			# TODO
		end
		
		t.test "minProperties" do |t|
			schema = JsonSchema.new(%({
				"minProperties": 2
			}))
			
			t.not_ok schema.validate(%(
				{ "a": 1 }
			)).valid
			
			t.ok schema.validate(%(
				{ "a": 1, "b": 2 }
			)).valid
		end
		
		t.test "maxProperties" do |t|
			schema = JsonSchema.new(%({
				"maxProperties": 2
			}))
			
			t.not_ok schema.validate(%(
				{ "a": 1, "b": 2, "c": 3 }
			)).valid
			
			t.ok schema.validate(%(
				{ "a": 1, "b": 2 }
			)).valid
		end
	end
	
	t.test "strings" do |t|
		
		t.test "minLength" do |t|
			schema = JsonSchema.new(%({
				"minLength": 3
			}))
			
			t.not_ok schema.validate(%(
				"ab"
			)).valid
			
			t.ok schema.validate(%(
				"abc"
			)).valid
		end
		
		t.test "maxLength" do |t|
			schema = JsonSchema.new(%({
				"maxLength": 3
			}))
			
			t.not_ok schema.validate(%(
				"abcd"
			)).valid
			
			t.ok schema.validate(%(
				"abc"
			)).valid
		end
	end
	
	t.test "sub-schemas" do |t|
		
		t.test "allOf" do |t|
			schema = JsonSchema.new(%({
				"type": "string",
				"allOf": [{
					"enum": [ "abc", "def" ]
				},{
					"enum": [ "abc", "ghi" ]
				},{
					"enum": [ "abc", "jkl" ]
				}]
			}))
			
			t.not_ok schema.validate(%(
				"def"
			)).valid
			
			t.ok schema.validate(%(
				"abc"
			)).valid
		end
		
		t.test "anyOf" do |t|
			schema = JsonSchema.new(%({
				"type": "string",
				"anyOf": [{
					"enum": [ "abc", "def" ]
				},{
					"enum": [ "abc", "ghi" ]
				},{
					"enum": [ "abc", "jkl" ]
				}]
			}))
			
			t.not_ok schema.validate(%(
				"mno"
			)).valid
			
			t.ok schema.validate(%(
				"def"
			)).valid
		end
		
		t.test "oneOf" do |t|
			schema = JsonSchema.new(%({
				"type": "string",
				"oneOf": [{
					"enum": [ "abc", "def" ]
				},{
					"enum": [ "abc", "ghi" ]
				},{
					"enum": [ "abc", "jkl" ]
				}]
			}))
			
			t.not_ok schema.validate(%(
				"abc"
			)).valid
			
			t.ok schema.validate(%(
				"def"
			)).valid
		end
		
		t.test "not" do |t|
			schema = JsonSchema.new(%({
				"type": "string",
				"not": {
					"enum": [ "abc", "def" ]
				}
			}))
			
			t.not_ok schema.validate(%(
				"abc"
			)).valid
			
			t.ok schema.validate(%(
				"ghi"
			)).valid
		end
	end
end
