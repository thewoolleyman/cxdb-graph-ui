#!/usr/bin/env ruby
# frozen_string_literal: true

# Verify a DOT file matches the values defined in a YAML config file.
# Checks: gate node existence + tool_command, model_stylesheet.
# Usage: ruby verify_dot.rb <yaml-file> <dot-file>

require "yaml"

yaml_path, dot_path = ARGV
if yaml_path.nil? || dot_path.nil?
  warn "Usage: verify_dot.rb <yaml-file> <dot-file>"
  exit 1
end

doc = YAML.safe_load(File.read(yaml_path), permitted_classes: [Symbol])
dot = File.read(dot_path)
errors = []

# Normalize whitespace for comparison: collapse runs of whitespace to single space, trim.
def normalize(s)
  s.gsub(/\s+/, " ").strip
end

# Unescape DOT string (reverse of dot_escape).
def dot_unescape(s)
  s.gsub('\\n', "\n").gsub('\\"', '"').gsub('\\\\', '\\')
end

# Extract the value of a named attribute from a node's [...] block.
# Scans all occurrences of the node ID in case there are multiple
# definitions (e.g. shape on one, prompt on another).
def extract_node_attr(dot, node_id, attr_name)
  id_re = Regexp.escape(node_id)
  attr_re = Regexp.escape(attr_name)
  block_re = /#{id_re}\s*\[(.*?)\]/m

  dot.scan(block_re).each do |captures|
    block = captures[0]
    value_re = /#{attr_re}\s*=\s*"((?:[^"\\]|\\.)*)"/m
    value_match = block.match(value_re)
    return dot_unescape(value_match[1]) if value_match
  end

  nil
end

# Extract a graph-level attribute.
def extract_graph_attr(dot, attr_name)
  graph_match = dot.match(/graph\s*\[(.*?)\]\s*\n/m)
  return nil unless graph_match

  block = graph_match[1]
  attr_re = /#{Regexp.escape(attr_name)}\s*=\s*"((?:[^"\\]|\\.)*)"/m
  value_match = block.match(attr_re)
  return nil unless value_match

  dot_unescape(value_match[1])
end

# Verify required gates
(doc["required_gates"] || []).each do |gate|
  id = gate["id"]

  # Check node exists with shape=parallelogram
  shape_re = /#{Regexp.escape(id)}\s*\[[^\]]*shape\s*=\s*parallelogram/m
  unless dot.match?(shape_re)
    errors << "MISSING NODE: \"#{id}\" not found as shape=parallelogram"
    next
  end

  # Check tool_command matches
  actual = extract_node_attr(dot, id, "tool_command")
  if actual.nil?
    errors << "MISSING ATTR: \"#{id}\" has no tool_command attribute"
  elsif normalize(actual) != normalize(gate["tool_command"])
    errors << <<~MSG.strip
      MISMATCH tool_command for "#{id}":
        YAML:   #{normalize(gate["tool_command"])}
        DOT:    #{normalize(actual)}
    MSG
  end
end

# Verify model_stylesheet
if doc["model_stylesheet"]
  actual = extract_graph_attr(dot, "model_stylesheet")
  if actual.nil?
    errors << "MISSING: model_stylesheet not found in graph attributes"
  elsif normalize(actual) != normalize(doc["model_stylesheet"])
    errors << <<~MSG.strip
      MISMATCH model_stylesheet:
        YAML:   #{normalize(doc["model_stylesheet"])[0, 120]}...
        DOT:    #{normalize(actual)[0, 120]}...
    MSG
  end
end

# Verify graph ID
if doc["graph_id"]
  graph_id_match = dot.match(/\Adigraph\s+(\S+)\s*\{/m)
  if graph_id_match
    actual_id = graph_id_match[1]
    if actual_id != doc["graph_id"]
      errors << "MISMATCH graph_id: YAML=#{doc["graph_id"]} DOT=#{actual_id}"
    end
  else
    errors << "MISSING: Could not parse graph ID from DOT"
  end
end

# Verify retry_target and fallback_retry_target
%w[retry_target fallback_retry_target].each do |attr|
  next unless doc[attr]
  actual = extract_graph_attr(dot, attr)
  if actual.nil?
    errors << "MISSING: #{attr} not found in graph attributes"
  elsif normalize(actual) != normalize(doc[attr])
    errors << "MISMATCH #{attr}: YAML=#{doc[attr]} DOT=#{actual}"
  end
end

# DOT keywords that aren't node IDs
dot_keywords = %w[graph digraph node edge subgraph]

# Verify node inventory
yaml_nodes = doc["nodes"] || []
unless yaml_nodes.empty?
  # Extract DOT node definitions with their shapes
  dot_nodes = {}
  dot.scan(/^\s*(\w+)\s*\[([^\]]*)\]/m).each do |id, attrs|
    next if dot_keywords.include?(id)
    shape_match = attrs.match(/shape\s*=\s*(\w+)/)
    dot_nodes[id] = shape_match ? shape_match[1] : nil
  end

  yaml_nodes.each do |node|
    id = node["id"]
    expected_shape = node["shape"]
    if dot_nodes.key?(id)
      if expected_shape && dot_nodes[id] && dot_nodes[id] != expected_shape
        errors << "SHAPE MISMATCH: node \"#{id}\" expected shape=#{expected_shape}, got shape=#{dot_nodes[id]}"
      end
    else
      errors << "MISSING NODE: \"#{id}\" from YAML inventory not found in DOT"
    end
  end

  # Flag extra box nodes not in YAML inventory
  yaml_ids = yaml_nodes.map { |n| n["id"] }
  dot_nodes.each do |id, shape|
    next if yaml_ids.include?(id)
    next unless shape == "box"
    errors << "EXTRA BOX NODE: \"#{id}\" has shape=box in DOT but is not in YAML node inventory"
  end
end

# Verify topology compliance
if doc["topology"] == "no-fanout"
  dot.scan(/^\s*(\w+)\s*\[([^\]]*)\]/m).each do |id, attrs|
    next if dot_keywords.include?(id)
    shape_match = attrs.match(/shape\s*=\s*(\w+)/)
    next unless shape_match
    shape = shape_match[1]
    if shape == "component"
      errors << "TOPOLOGY VIOLATION: node \"#{id}\" has shape=component (forbidden in no-fanout topology)"
    end
    if shape == "tripleoctagon"
      errors << "TOPOLOGY VIOLATION: node \"#{id}\" has shape=tripleoctagon (forbidden in no-fanout topology)"
    end
  end
end

# Verify edges
yaml_edges = doc["edges"] || []
unless yaml_edges.empty?
  # Extract edges from DOT: "from -> to" with optional [...] attributes
  dot_edges = []
  dot.scan(/^\s*(\w+)\s*->\s*(\w+)(?:\s*\[([^\]]*)\])?/m).each do |from, to, attrs_str|
    edge = { "from" => from, "to" => to }
    if attrs_str
      cond_match = attrs_str.match(/condition\s*=\s*"([^"]*)"/)
      edge["condition"] = cond_match[1] if cond_match
      edge["loop_restart"] = true if attrs_str.match?(/loop_restart\s*=\s*true/)
      label_match = attrs_str.match(/label\s*=\s*"([^"]*)"/)
      edge["label"] = label_match[1] if label_match
    end
    dot_edges << edge
  end

  yaml_edges.each_with_index do |yaml_edge, idx|
    # Find matching edge in DOT
    match = dot_edges.find do |de|
      de["from"] == yaml_edge["from"] &&
        de["to"] == yaml_edge["to"] &&
        de["condition"] == yaml_edge["condition"] &&
        (yaml_edge["loop_restart"] ? de["loop_restart"] == true : !de["loop_restart"])
    end

    unless match
      desc = "#{yaml_edge["from"]} -> #{yaml_edge["to"]}"
      desc += " [condition=\"#{yaml_edge["condition"]}\"]" if yaml_edge["condition"]
      desc += " [loop_restart=true]" if yaml_edge["loop_restart"]
      errors << "MISSING EDGE ##{idx}: #{desc}"
    end
  end
end

# Report
if errors.empty?
  gate_ids = (doc["required_gates"] || []).map { |g| g["id"] }.join(", ")
  puts "PASS: #{dot_path} matches #{yaml_path}"
  puts "  Gates verified: #{gate_ids}"
  puts "  model_stylesheet: OK"
  puts "  graph_id: #{doc["graph_id"] || "n/a"}"
  puts "  retry_target: #{doc["retry_target"] || "n/a"}"
  puts "  fallback_retry_target: #{doc["fallback_retry_target"] || "n/a"}"
  puts "  node_inventory: #{yaml_nodes.length} nodes verified" unless yaml_nodes.empty?
  puts "  edges: #{yaml_edges.length} edges verified" unless yaml_edges.empty?
  puts "  topology: #{doc["topology"] || "n/a"}"
  exit 0
else
  warn "FAIL: #{errors.length} error(s) in #{dot_path}:\n"
  errors.each { |err| warn "  #{err}\n" }
  exit 1
end
