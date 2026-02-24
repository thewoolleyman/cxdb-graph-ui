#!/usr/bin/env ruby
# frozen_string_literal: true

# Extract a single top-level field from a YAML file and write it to stdout.
# Usage: ruby extract_field.rb <yaml-file> <field-name>

require "yaml"
require "json"

yaml_path, field_name = ARGV
if yaml_path.nil? || field_name.nil?
  warn "Usage: extract_field.rb <yaml-file> <field-name>"
  exit 1
end

doc = YAML.safe_load(File.read(yaml_path), permitted_classes: [Symbol])

unless doc.key?(field_name)
  warn "Field \"#{field_name}\" not found in #{yaml_path}"
  exit 1
end

value = doc[field_name]
if value.is_a?(String)
  $stdout.write(value)
else
  $stdout.write(JSON.pretty_generate(value))
end
