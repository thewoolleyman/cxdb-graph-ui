#!/usr/bin/env ruby
# frozen_string_literal: true

# Deterministic DOT compiler: assembles a complete DOT file from a YAML config
# and per-node prompt files. No LLM involved — same input always produces
# byte-identical output.
#
# Usage: ruby compile_dot.rb <yaml-file> [output-dot-file]
#
# If output-dot-file is omitted, writes to stdout.

require "yaml"
require "pathname"
require "digest"

yaml_path = ARGV[0]
output_path = ARGV[1]

if yaml_path.nil?
  warn "Usage: compile_dot.rb <yaml-file> [output-dot-file]"
  exit 1
end

doc = YAML.safe_load(File.read(yaml_path), permitted_classes: [Symbol])
yaml_dir = Pathname.new(yaml_path).expand_path.dirname
target = doc["target"]

unless target
  warn "ERROR: YAML config missing 'target' field"
  exit 1
end

# --- Helpers ---

# Escape a string for use inside a DOT "..." attribute value.
def dot_escape(s)
  s.gsub('\\', '\\\\\\\\').gsub('"', '\\"')
end

# Build a gate lookup: id -> { tool_command:, timeout:, max_retries: }
def build_gate_lookup(doc)
  lookup = {}
  (doc["required_gates"] || []).each do |gate|
    lookup[gate["id"]] = gate
  end
  lookup
end

# Resolve a prompt file for a node. Convention: <yaml_dir>/<node_id>.md
def resolve_prompt_file(yaml_dir, target, node_id)
  yaml_dir.join("#{node_id}.md")
end

# Read a prompt file, stripping trailing whitespace but preserving internal formatting.
def read_prompt(yaml_dir, target, node_id)
  path = resolve_prompt_file(yaml_dir, target, node_id)
  unless path.exist?
    warn "ERROR: Prompt file not found: #{path}"
    exit 1
  end
  File.read(path).strip
end

# --- Build the DOT output ---

lines = []
gate_lookup = build_gate_lookup(doc)

# Config checksum
config_sha256 = Digest::SHA256.hexdigest(File.read(yaml_path))

# Graph header
graph_id = doc["graph_id"] || "pipeline"
lines << "digraph #{graph_id} {"

# Graph attributes
graph_goal = doc["graph_goal"] || doc["goal"].to_s.lines.first&.strip || ""
default_max_retry = doc["default_max_retry"] || 3
retry_target = doc["retry_target"]
fallback_retry_target = doc["fallback_retry_target"]
model_stylesheet = doc["model_stylesheet"]

graph_attrs = []
graph_attrs << "    config_sha256=\"#{config_sha256}\""
graph_attrs << "    goal=\"#{dot_escape(graph_goal)}\""
graph_attrs << "    rankdir=LR"
graph_attrs << "    default_max_retry=#{default_max_retry}"
graph_attrs << "    retry_target=\"#{dot_escape(retry_target)}\"" if retry_target
graph_attrs << "    fallback_retry_target=\"#{dot_escape(fallback_retry_target)}\"" if fallback_retry_target

if model_stylesheet
  escaped_stylesheet = dot_escape(model_stylesheet.rstrip)
  graph_attrs << "    model_stylesheet=\"\n#{escaped_stylesheet}\n    \""
end

lines << "  graph ["
lines << graph_attrs.join(",\n")
lines << "  ]"
lines << ""

# Node declarations (in YAML order)
nodes = doc["nodes"] || []
nodes.each do |node|
  id = node["id"]
  shape = node["shape"]

  case shape
  when "Mdiamond", "Msquare"
    lines << "  #{id} [shape=#{shape}]"

  when "box"
    attrs = ["shape=box"]
    attrs << "class=\"#{node["class"]}\"" if node["class"]
    attrs << "goal_gate=true" if node["goal_gate"]

    # Load prompt
    if id == "expand_spec" && doc["expand_spec_prompt"]
      prompt_text = doc["expand_spec_prompt"].strip
    else
      prompt_text = read_prompt(yaml_dir, target, id)
    end

    escaped_prompt = dot_escape(prompt_text)
    attrs << "prompt=\"#{escaped_prompt}\""

    lines << "  #{id} [#{attrs.join(", ")}]"

  when "parallelogram"
    attrs = ["shape=parallelogram"]

    # Look up gate info
    gate = gate_lookup[id]
    if gate
      attrs << "max_retries=#{gate["max_retries"]}" if gate["max_retries"]
      attrs << "tool_command=\"#{dot_escape(gate["tool_command"])}\""
      attrs << "timeout=\"#{gate["timeout"]}\"" if gate["timeout"]
    else
      warn "WARNING: parallelogram node \"#{id}\" has no required_gates entry"
    end

    lines << "  #{id} [#{attrs.join(", ")}]"

  when "diamond"
    lines << "  #{id} [shape=diamond]"

  when "hexagon"
    attrs = ["shape=hexagon"]

    # Load question from prompt file
    question_file = resolve_prompt_file(yaml_dir, target, id)
    if question_file.exist?
      question_text = File.read(question_file).strip
      attrs << "question=\"#{dot_escape(question_text)}\""
    end

    # Hexagon choice attribute — different pipelines use different names
    %w[choices options edges].each do |attr_name|
      if node[attr_name]
        attrs << "#{attr_name}=\"#{dot_escape(node[attr_name])}\""
      end
    end

    lines << "  #{id} [#{attrs.join(", ")}]"

  else
    # Unknown shape — emit as-is
    attrs = ["shape=#{shape}"]
    lines << "  #{id} [#{attrs.join(", ")}]"
  end
end

lines << ""

# Edge declarations (in YAML order)
edges = doc["edges"] || []
edges.each do |edge|
  attrs = []
  attrs << "condition=\"#{edge["condition"]}\"" if edge["condition"]
  attrs << "loop_restart=true" if edge["loop_restart"]
  attrs << "label=\"#{dot_escape(edge["label"])}\"" if edge["label"]

  if attrs.empty?
    lines << "  #{edge["from"]} -> #{edge["to"]}"
  else
    lines << "  #{edge["from"]} -> #{edge["to"]} [#{attrs.join(", ")}]"
  end
end

lines << "}"
lines << "" # trailing newline

output = lines.join("\n")

if output_path
  File.write(output_path, output)
  warn "Compiled #{output_path} (#{output.lines.count} lines, sha256=#{config_sha256[0..11]}...)"
else
  puts output
end
