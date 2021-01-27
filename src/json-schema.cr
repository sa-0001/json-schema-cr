require "json-typeof"

##======================================================================================================================

class JsonSchema
	
	class Result
		def initialize (@valid, @asserts, @errors, @output) end
		getter valid : Bool
		getter asserts : Array(String)
		getter errors : Array(String)
		getter output : JSON::Any
	end
	
	@schema : JSON::Any
	
	def initialize (schema : String | JSON::Any, root_name = "$")
		if schema.is_a? String
			@schema = JSON.parse schema
		else
			@schema = schema
		end
		
		pass = [] of String
		fail = [] of String
		verify_schema @schema, pass, fail, root_name
		# puts "schema.pass", pass.join "\n"
		# puts "schema.fail", fail.join "\n"
		if !fail.empty?
			raise %(JsonSchema: invalid schema:\n) + fail.join "\n"
		end
	end
	
	def verify_schema (schema : JSON::Any, pass, fail, field)
		ok = schema.typeof == JSON::Typeof::Object
		( ok ? pass : fail ).push error_schema field
		return unless ok
		
		@@operators.each do |name, config|
			# skip if not present in schema
			next unless schema.as_h.has_key? name
			
			# check argument type against operator.argument_types
			if types = config[:argument_types]
				ok = types.includes? schema[name].typeof.to_s
				( ok ? pass : fail ).push error_operator_argument field, name, types
			end
			
			case name
				# array of objects which are schemas
				when "allOf", "anyOf", "oneOf", "items"
					schema[name].as_a.each_with_index do |subschema, index|
						verify_schema subschema, pass, fail, %(#{field}.#{name}[#{index}])
					end
				
				# object which is a schema
				when "additionalItems", "additionalProperties", "not"
					# additionalItems & additionalProperties may also be a boolean
					next unless schema[name].typeof == JSON::Typeof::Object
					
					verify_schema schema[name], pass, fail, %(#{field}.#{name})
				
				# object whose values are schemas
				when "properties"
					schema[name].as_h.each do |key, subschema|
						verify_schema subschema, pass, fail, %(#{field}.#{name}.#{key})
					end
			end
		end
	end
	
	##--------------------------------------------------------------------------
	
	def validate (raw_input : String | JSON::Any | Nil, schema_root_field = "$", input_root_field = "$")
		if raw_input.is_a? String
			input = JSON.parse raw_input
		else
			input = raw_input
		end
		
		pass = [] of String
		fail = [] of String
		_validate @schema, input, pass, fail, schema_root_field, input_root_field
		
		# return Result.new fail.empty?, pass, fail, input
		return Result.new valid: fail.empty?, asserts: pass, errors: fail, output: input
	end
	
	def _validate (schema : JSON::Any, input : JSON::Any | Nil, pass, fail, schema_field, input_field)
		pass_count = pass.size
		fail_count = fail.size
		
		@@operators.each do |name, config|
			# skip if not present in schema
			next unless schema.as_h.has_key? name
			
			input_typeof = input ? input.typeof.to_s : "undefined"
			
			# check input type against operator.input_types
			if types = config[:input_types]
				ok = types.includes? input_typeof
				( ok ? pass : fail ).push error_operator_input input_field, name, types
				next if !ok
			end
			
			case name
				# any
				
				when "const"
					ok = schema[name] == input
					( ok ? pass : fail ).push error_const input_field, schema[name]
				
				when "enum"
					ok = schema[name].as_a.includes? input
					( ok ? pass : fail ).push error_enum input_field, schema[name].as_a
				
				when "nullable"
					ok = schema[name].as_bool == true || input_typeof != "null"
					( ok ? pass : fail ).push error_nullable input_field, ok
				
				when "required"
					ok = schema[name].as_bool == false || input != nil
					( ok ? pass : fail ).push error_required input_field, ok
				
				when "type"
					is_nullable = schema.as_h.has_key?("nullable") && schema["nullable"].as_bool == true
					
					# special case: input type "integer" is also allowed for schema type "number"
					is_integer = input_typeof == "integer"
					
					ok = schema[name].to_s == input_typeof || (is_integer && schema[name].to_s == "number") || (is_nullable && input_typeof == "null")
					( ok ? pass : fail ).push error_type input_field, schema[name].to_s + (is_nullable ? "?" : ""), input_typeof
				
				# arrays
				
				when "items"
					schema["items"].as_a.each_with_index do |val, key|
						_validate val, input.not_nil!.as_a.fetch(key, nil), pass, fail, %(#{schema_field}.items[#{key}]), %(#{input_field}[#{key}])
					end
				when "additionalItems"
					if schema[name].typeof == JSON::Typeof::Boolean && schema[name].as_bool == false
						# may not contain more items than found in "items"
						schema_keys = schema.as_h.has_key?("items") ? ( 0 .. (schema["items"].as_a.size - 1) ).to_a : [] of Int32
						input_keys = ( 0 .. (input.not_nil!.as_a.size - 1) ).to_a
						
						diff_keys = input_keys - schema_keys
						
						ok = diff_keys.empty?
						( ok ? pass : fail ).push error_additional_items input_field, diff_keys
					else
						input.not_nil!.as_a.each_with_index do |val, key|
							# skip items already defined in "items"
							next if schema.as_h.has_key?("items") && !schema["items"].as_a.fetch(key, nil).nil?
							
							_validate schema[name], val, pass, fail, %(#{schema_field}.additionalItems), %(#{input_field}[#{key}])
						end
					end
				
				when "minItems"
					expect = schema[name].as_i
					actual = input.not_nil!.as_a.size
					
					ok = actual >= expect
					( ok ? pass : fail ).push error_min_items input_field, expect, actual
				when "maxItems"
					expect = schema[name].as_i
					actual = input.not_nil!.as_a.size
					
					ok = actual <= expect
					( ok ? pass : fail ).push error_max_items input_field, expect, actual
				
				when "uniqueItems"
					item_count = input.not_nil!.as_a.size
					unique_item_count = input.not_nil!.as_a.uniq.size
					
					ok = schema[name].as_bool == false || item_count == unique_item_count
					( ok ? pass : fail ).push error_unique_items input_field
				
				# integers & numbers
				
				when "minimum"
					is_exclusive = schema.as_h.has_key?("exclusiveMinimum") && schema["exclusiveMinimum"].as_bool == true
					
					expect = schema[name].typeof == JSON::Typeof::Integer ? schema[name].as_i.to_f64 : schema[name].as_f
					actual = input.not_nil!.typeof == JSON::Typeof::Integer ? input.not_nil!.as_i.to_f64 : input.not_nil!.as_f
					
					ok = is_exclusive ? (actual > expect) : (actual >= expect)
					( ok ? pass : fail ).push error_minimum input_field, expect, actual, is_exclusive
				
				when "maximum"
					is_exclusive = schema.as_h.has_key?("exclusiveMaximum") && schema["exclusiveMaximum"].as_bool == true
					
					expect = schema[name].typeof == JSON::Typeof::Integer ? schema[name].as_i.to_f64 : schema[name].as_f
					actual = input.not_nil!.typeof == JSON::Typeof::Integer ? input.not_nil!.as_i.to_f64 : input.not_nil!.as_f
					
					ok = is_exclusive ? (actual < expect) : (actual <= expect)
					( ok ? pass : fail ).push error_maximum input_field, expect, actual, is_exclusive
				
				when "multipleOf"
					expect = schema[name].typeof == JSON::Typeof::Integer ? schema[name].as_i.to_f64 : schema[name].as_f
					actual = input.not_nil!.typeof == JSON::Typeof::Integer ? input.not_nil!.as_i.to_f64 : input.not_nil!.as_f
					
					ok = actual % expect == 0
					( ok ? pass : fail ).push error_multiple input_field, expect, actual
				
				# objects
				
				when "properties"
					schema["properties"].as_h.each do |key, val|
						_validate val, input.not_nil!.as_h.fetch(key, nil), pass, fail, %(#{schema_field}.properties.#{key}), %(#{input_field}.#{key})
					end
				when "additionalProperties"
					if schema[name].typeof == JSON::Typeof::Boolean && schema[name].as_bool == false
						# may not contain more properties than found in "properties"
						schema_keys = schema.as_h.has_key?("properties") ? schema["properties"].as_h.keys : [] of String
						input_keys = input.not_nil!.as_h.keys
						
						diff_keys = input_keys - schema_keys
						
						ok = diff_keys.empty?
						( ok ? pass : fail ).push error_additional_properties input_field, diff_keys
					else
						input.not_nil!.as_h.each do |key, val|
							# skip properties already defined in "properties"
							next if schema.as_h.has_key?("properties") && schema["properties"].as_h.has_key? key
							
							_validate schema[name], val, pass, fail, %(#{schema_field}.additionalProperties), %(#{input_field}.#{key})
						end
					end
				
				when "minProperties"
					expect = schema[name].as_i
					actual = input.not_nil!.as_h.size
					
					ok = actual >= expect
					( ok ? pass : fail ).push error_min_properties input_field, expect, actual
				when "maxProperties"
					expect = schema[name].as_i
					actual = input.not_nil!.as_h.size
					
					ok = actual <= expect
					( ok ? pass : fail ).push error_max_properties input_field, expect, actual
				
				# strings
				
				when "format"
					# some taken from AJV: https://github.com/ajv-validator/ajv-formats
					regex = case schema[name].as_s
						when "binary"    then nil # informational
						when "byte"      then nil # informational
						when "date-time" then /^[\d]{4}-[0-1]\d-[0-3]\dT[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?(Z|[+-][0-9]{2}:[0-9]{2})$/
						when "date"      then /^[\d]{4}-[0-1]\d-[0-3]\d$/
						when "email"     then /^[\w-\.]+@([\w-]+\.)+[\w-]+$/
						when "hostname"  then /^([\w-]+\.)+[\w-]+$/
						when "ipv4"      then /^(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)$/
						when "ipv6"      then /^((([0-9a-f]{1,4}:){7}([0-9a-f]{1,4}|:))|(([0-9a-f]{1,4}:){6}(:[0-9a-f]{1,4}|((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9a-f]{1,4}:){5}(((:[0-9a-f]{1,4}){1,2})|:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9a-f]{1,4}:){4}(((:[0-9a-f]{1,4}){1,3})|((:[0-9a-f]{1,4})?:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9a-f]{1,4}:){3}(((:[0-9a-f]{1,4}){1,4})|((:[0-9a-f]{1,4}){0,2}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9a-f]{1,4}:){2}(((:[0-9a-f]{1,4}){1,5})|((:[0-9a-f]{1,4}){0,3}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9a-f]{1,4}:){1}(((:[0-9a-f]{1,4}){1,6})|((:[0-9a-f]{1,4}){0,4}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(:(((:[0-9a-f]{1,4}){1,7})|((:[0-9a-f]{1,4}){0,5}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:)))$/i
						when "password"  then nil # informational
						when "time"      then /^[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?$/
						when "uri"       then /^(?:[a-z][a-z0-9+\-.]*:)(?:\/?\/)?[^\s]*$/i
						when "uuid"      then /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i
						else nil # informational
					end
					
					ok = regex ? regex.matches?(input.not_nil!.as_s) : true
					( ok ? pass : fail ).push error_format input_field, schema[name].as_s
				
				when "minLength"
					ok = input.not_nil!.as_s.size >= schema[name].as_i
					( ok ? pass : fail ).push error_min_length input_field, schema[name].as_i
				
				when "maxLength"
					ok = input.not_nil!.as_s.size <= schema[name].as_i
					( ok ? pass : fail ).push error_max_length input_field, schema[name].as_i
				
				when "pattern"
					regex = Regex.new schema[name].as_s
					
					ok = regex.matches? input.not_nil!.as_s
					( ok ? pass : fail ).push error_pattern input_field, schema[name].as_s
				
				# sub-schemas
				
				when "allOf"
					count = 0
					schema[name].as_a.each_with_index do |subschema, index|
						subpass = [] of String
						subfail = [] of String
						ok = _validate subschema, input, subpass, subfail, %(#{schema_field}.allOf[#{index}]), input_field
						pass.concat subpass
						count += 1 if ok
					end
					ok = count == schema[name].as_a.size
					( ok ? pass : fail ).push error_all_of input_field
				
				when "anyOf"
					count = 0
					schema[name].as_a.each_with_index do |subschema, index|
						subpass = [] of String
						subfail = [] of String
						ok = _validate subschema, input, subpass, subfail, %(#{schema_field}.anyOf[#{index}]), input_field
						pass.concat subpass
						count += 1 if ok
					end
					ok = count > 0
					( ok ? pass : fail ).push error_any_of input_field
				
				when "oneOf"
					count = 0
					schema[name].as_a.each_with_index do |subschema, index|
						subpass = [] of String
						subfail = [] of String
						ok = _validate subschema, input, subpass, subfail, %(#{schema_field}.oneOf[#{index}]), input_field
						pass.concat subpass
						count += 1 if ok
					end
					ok = count == 1
					( ok ? pass : fail ).push error_one_of input_field
				
				when "not"
					subpass = [] of String
					subfail = [] of String
					ok = !_validate schema[name], input, subpass, subfail, %(#{schema_field}.not), input_field
					pass.concat subpass
					( ok ? pass : fail ).push error_not input_field
				
			end
		end
		
		# if any fail asserts were added, then this _validate step has failed
		return fail_count == fail.size
	end
	
	@@operators = {
		# any
		
		"const" => {
			argument_types: nil,
			input_types: nil,
		},
		"enum" => {
			argument_types: [ "array" ],
			input_types: nil,
		},
		"nullable" => {
			argument_types: [ "boolean" ],
			input_types: nil,
		},
		"required" => {
			argument_types: [ "boolean" ],
			input_types: nil,
		},
		"type" => {
			argument_types: [ "string" ],
			input_types: nil,
		},
		
		# arrays
		
		"items" => {
			argument_types: [ "array" ],
			input_types: [ "array" ],
		},
		"additionalItems" => {
			argument_types: [ "boolean", "object" ],
			input_types: [ "array" ],
		},
		"minItems" => {
			argument_types: [ "integer" ],
			input_types: [ "array" ],
		},
		"maxItems" => {
			argument_types: [ "integer" ],
			input_types: [ "array" ],
		},
		"uniqueItems" => {
			argument_types: [ "boolean" ],
			input_types: [ "array" ],
		},
		
		# objects
		
		"properties" => {
			argument_types: [ "object" ],
			input_types: [ "object" ],
		},
		"additionalProperties" => {
			argument_types: [ "boolean", "object" ],
			input_types: [ "object" ],
		},
		"minProperties" => {
			argument_types: [ "integer" ],
			input_types: [ "object" ],
		},
		"maxProperties" => {
			argument_types: [ "integer" ],
			input_types: [ "object" ],
		},
		
		# integers & numbers
		
		"minimum" => {
			argument_types: [ "integer", "number" ],
			input_types: [ "integer", "number" ],
		},
		"exclusiveMinimum" => {
			argument_types: [ "boolean" ],
			input_types: [ "integer", "number" ],
		},
		"maximum" => {
			argument_types: [ "integer", "number" ],
			input_types: [ "integer", "number" ],
		},
		"exclusiveMaximum" => {
			argument_types: [ "boolean" ],
			input_types: [ "integer", "number" ],
		},
		"multipleOf" => {
			argument_types: [ "integer", "number" ],
			input_types: [ "integer", "number" ],
		},
		
		# strings
		
		"format" => {
			argument_types: [ "string" ],
			input_types: [ "string" ],
		},
		"minLength" => {
			argument_types: [ "integer" ],
			input_types: [ "string" ],
		},
		"maxLength" => {
			argument_types: [ "integer" ],
			input_types: [ "string" ],
		},
		"pattern" => {
			argument_types: [ "string" ],
			input_types: [ "string" ],
		},
		
		# sub-schemas
		
		"allOf" => {
			argument_types: [ "array" ],
			input_types: nil,
		},
		"anyOf" => {
			argument_types: [ "array" ],
			input_types: nil,
		},
		"oneOf" => {
			argument_types: [ "array" ],
			input_types: nil,
		},
		"not" => {
			argument_types: [ "object" ],
			input_types: nil,
		},
		
		# # TODO
		
		# # any
		# default
		
		# # object
		# required
	}
	
	# schema
	
	def error_schema (field)
		%(field #{field.to_json}: schema is an object)
	end
	
	def error_operator_argument (field, name, types)
		%(field #{field.to_json}: operator #{name.to_json} requires argument types #{types.map(&.to_json).join(", ")})
	end
	def error_operator_input (field, name, types)
		%(field #{field.to_json}: operator #{name.to_json} requires input types #{types.map(&.to_json).join(", ")})
	end
	
	# any
	
	def error_const (field, val)
		%(field #{field.to_json}: constant value #{val.to_json})
	end
	def error_enum (field, vals)
		%(field #{field.to_json}: enum values #{vals.map(&.to_json).join(", ")})
	end
	def error_nullable (field, ok)
		%(field #{field.to_json}: is nullable)
	end
	def error_required (field, ok)
		%(field #{field.to_json}: is required)
	end
	def error_type (field, expect, actual)
		%(field #{field.to_json}: expect #{expect.to_json} actual #{actual.to_json})
	end
	
	# arrays
	
	def error_additional_items (field, keys)
		%(field #{field.to_json}: does not allow additionalItems #{keys.join(",")})
	end
	def error_min_items (field, expect, actual)
		%(field #{field.to_json}: #{actual} >= minimum items #{expect})
	end
	def error_max_items (field, expect, actual)
		%(field #{field.to_json}: #{actual} <= maximum items #{expect})
	end
	def error_unique_items (field)
		%(field #{field.to_json}: has unique items)
	end
	
	# integers & numbers
	
	def error_minimum (field, expect, actual, excl)
		%(field #{field.to_json}: #{actual} #{excl ? ">" : ">="} #{expect})
	end
	def error_maximum (field, expect, actual, excl)
		%(field #{field.to_json}: #{actual} #{excl ? "<" : "<="} #{expect})
	end
	def error_multiple (field, expect, actual)
		%(field #{field.to_json}: #{actual} is a multiple of #{expect})
	end
	
	# objects
	
	def error_additional_properties (field, keys)
		%(field #{field.to_json}: does not allow additionalProperties #{keys.join(",")})
	end
	def error_min_properties (field, expect, actual)
		%(field #{field.to_json}: #{actual} >= minimum properties #{expect})
	end
	def error_max_properties (field, expect, actual)
		%(field #{field.to_json}: #{actual} <= maximum properties #{expect})
	end
	
	# strings
	
	def error_format (field, format)
		%(field #{field.to_json}: does not match format "#{format}")
	end
	def error_min_length (field, len)
		%(field #{field.to_json}: minimum length #{len})
	end
	def error_max_length (field, len)
		%(field #{field.to_json}: maximum length #{len})
	end
	def error_pattern (field, pattern)
		%(field #{field.to_json}: does not match pattern "#{pattern}")
	end
	
	# sub-schemas
	
	def error_all_of (field)
		%(field #{field.to_json}: allOf)
	end
	def error_any_of (field)
		%(field #{field.to_json}: anyOf)
	end
	def error_one_of (field)
		%(field #{field.to_json}: oneOf)
	end
	def error_not (field)
		%(field #{field.to_json}: not)
	end
end
