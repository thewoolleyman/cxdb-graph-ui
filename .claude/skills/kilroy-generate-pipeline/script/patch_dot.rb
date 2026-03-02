#!/usr/bin/env ruby
# frozen_string_literal: true

# Patch a DOT file in-place using values from a YAML config file.
# Patches: tool_command on gate nodes, model_stylesheet.
# Usage: ruby patch_dot.rb <yaml-file> <dot-file>

require "yaml"

yaml_path, dot_path = ARGV
if yaml_path.nil? || dot_path.nil?
  warn "Usage: patch_dot.rb <yaml-file> <dot-file>"
  exit 1
end

doc = YAML.safe_load(File.read(yaml_path), permitted_classes: [Symbol])
dot = File.read(dot_path)
patch_count = 0

# Escape a string for use as a DOT attribute value (inside double quotes).
def dot_escape(s)
  s.gsub('\\', '\\\\\\\\').gsub('"', '\\"')
end

# Escape for single-line DOT attributes (newlines become literal \n).
def dot_escape_single_line(s)
  dot_escape(s).gsub("\n", '\\n')
end

# Patch tool_command and timeout on gate nodes
(doc["required_gates"] || []).each do |gate|
  id = Regexp.escape(gate["id"])
  # Match the node definition by ID with a tool_command attribute
  re = /(#{id}\s*\[[^\]]*?tool_command\s*=\s*")((?:[^"\\]|\\.)*)(")/m
  if dot.match?(re)
    escaped = dot_escape(gate["tool_command"])
    dot.sub!(re, "\\1#{escaped}\\3")
    patch_count += 1
    warn "Patched tool_command for #{gate["id"]}"
  else
    warn "WARNING: Node \"#{gate["id"]}\" with tool_command not found in #{dot_path}"
  end

  # Patch timeout if specified in YAML
  next unless gate["timeout"]
  timeout_val = gate["timeout"]
  # Match existing timeout attribute on this node
  timeout_re = /(#{id}\s*\[[^\]]*?)timeout\s*=\s*"[^"]*"([^\]]*\])/m
  if dot.match?(timeout_re)
    dot.sub!(timeout_re, "\\1timeout=\"#{timeout_val}\"\\2")
    patch_count += 1
    warn "Patched timeout for #{gate["id"]}"
  else
    # No existing timeout attribute — inject one after tool_command
    inject_re = /(#{id}\s*\[[^\]]*?tool_command\s*=\s*"(?:[^"\\]|\\.)*")(,?\s*)/m
    if dot.match?(inject_re)
      dot.sub!(inject_re, "\\1, timeout=\"#{timeout_val}\"\\2")
      patch_count += 1
      warn "Injected timeout for #{gate["id"]}"
    else
      warn "WARNING: Could not inject timeout for #{gate["id"]}"
    end
  end
end

# Patch model_stylesheet
if doc["model_stylesheet"]
  re = /(model_stylesheet\s*=\s*")((?:[^"\\]|\\.)*?)(")/m
  if dot.match?(re)
    escaped = dot_escape(doc["model_stylesheet"].rstrip)
    dot.sub!(re, "\\1\n#{escaped}\n    \\3")
    patch_count += 1
    warn "Patched model_stylesheet"
  else
    warn "WARNING: model_stylesheet not found"
  end
end

# Patch graph ID
graph_id = doc["graph_id"]
if graph_id
  if dot.sub!(/\Adigraph\s+\S+/, "digraph #{graph_id}")
    patch_count += 1
    warn "Patched graph ID to #{graph_id}"
  else
    warn "WARNING: Could not patch graph ID"
  end
end

# Patch graph-level retry_target and fallback_retry_target
%w[retry_target fallback_retry_target].each do |attr|
  next unless doc[attr]
  value = doc[attr]
  # Try to replace existing attribute
  existing_re = /(#{Regexp.escape(attr)}\s*=\s*")((?:[^"\\]|\\.)*)(")/m
  if dot.match?(existing_re)
    dot.sub!(existing_re, "\\1#{dot_escape(value)}\\3")
    patch_count += 1
    warn "Patched #{attr} to #{value}"
  else
    # Inject after goal attribute in graph block
    inject_re = /(goal\s*=\s*"(?:[^"\\]|\\.)*")(,?\s*\n)/m
    if dot.sub!(inject_re, "\\1,\n    #{attr}=\"#{dot_escape(value)}\"\\2")
      patch_count += 1
      warn "Injected #{attr}=#{value}"
    else
      warn "WARNING: Could not inject #{attr}"
    end
  end
end

# Normalize condition expression spacing
# Only inside condition="..." values
dot.gsub!(/condition\s*=\s*"([^"]*)"/) do |_match|
  val = Regexp.last_match(1)
  # Normalize multi-char operators first: !=, >=, <=
  val = val.gsub(/\s*!=\s*/, " != ")
  val = val.gsub(/\s*>=\s*/, " >= ")
  val = val.gsub(/\s*<=\s*/, " <= ")
  # Normalize single = (not preceded by !, >, <)
  val = val.gsub(/(?<![!><])\s*=\s*(?!=)/, " = ")
  # Normalize && spacing
  val = val.gsub(/\s*&&\s*/, " && ")
  # Collapse multiple spaces
  val = val.gsub(/  +/, " ").strip
  "condition=\"#{val}\""
end
warn "Normalized condition expression spacing"

# Node inventory warning
yaml_nodes = (doc["nodes"] || []).map { |n| n["id"] }
unless yaml_nodes.empty?
  # Extract node IDs from DOT (lines like: node_id [...] or node_id [shape=...])
  # Exclude "graph", "digraph", "node", "edge" which are DOT keywords, not node IDs
  dot_node_ids = dot.scan(/^\s*(\w+)\s*\[/).flatten.uniq - %w[graph digraph node edge subgraph]
  missing = yaml_nodes - dot_node_ids
  extra = dot_node_ids - yaml_nodes
  missing.each { |n| warn "WARNING: YAML node \"#{n}\" not found in DOT" }
  extra.each { |n| warn "NOTE: DOT node \"#{n}\" not in YAML inventory" }
end

File.write(dot_path, dot)
warn "\nDone: #{patch_count} patch(es) applied to #{dot_path}"
