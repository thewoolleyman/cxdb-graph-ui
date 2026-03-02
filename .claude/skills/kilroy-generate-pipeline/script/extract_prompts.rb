#!/usr/bin/env ruby
# frozen_string_literal: true

# Extract prompt and question text from a DOT file into per-node markdown files.
#
# For each shape=box node with a prompt attribute, writes:
#   <yaml_dir>/prompts/<node_id>.md
#
# For each shape=hexagon node with a question attribute, writes:
#   <yaml_dir>/prompts/<node_id>.md
#
# Usage: ruby extract_prompts.rb <yaml-file> <dot-file>

require "yaml"
require "pathname"
require "fileutils"

yaml_path, dot_path = ARGV
if yaml_path.nil? || dot_path.nil?
  warn "Usage: extract_prompts.rb <yaml-file> <dot-file>"
  exit 1
end

doc = YAML.safe_load(File.read(yaml_path), permitted_classes: [Symbol])
dot = File.read(dot_path)
target = doc["target"]

unless target
  warn "ERROR: YAML config missing 'target' field"
  exit 1
end

# Resolve output directory relative to the YAML file location.
yaml_dir = Pathname.new(yaml_path).expand_path.dirname
prompts_dir = yaml_dir.join("prompts")
FileUtils.mkdir_p(prompts_dir)

# Unescape DOT string values.
def dot_unescape(s)
  s.gsub('\\n', "\n").gsub('\\"', '"').gsub('\\\\', '\\')
end

# Extract the full [...] attribute block for a node, handling ] inside quoted strings.
# Returns the content between [ and the matching ].
def extract_attr_block(dot, node_id)
  id_re = Regexp.escape(node_id)
  start_re = /^\s*#{id_re}\s*\[/m

  blocks = []
  pos = 0
  while (match = dot.match(start_re, pos))
    block_start = match.end(0)
    # Walk through characters, tracking quoted strings
    i = block_start
    depth = 1
    in_quote = false
    escaped = false
    while i < dot.length && depth > 0
      ch = dot[i]
      if escaped
        escaped = false
      elsif ch == '\\'
        escaped = true
      elsif ch == '"'
        in_quote = !in_quote
      elsif !in_quote
        depth += 1 if ch == "["
        depth -= 1 if ch == "]"
      end
      i += 1
    end
    blocks << dot[block_start...i - 1] if depth == 0
    pos = i
  end
  blocks
end

# Extract a named attribute value from a node's [...] block(s).
# Handles multi-line attribute blocks, quoted strings containing ], and
# multiple definitions of the same node.
def extract_node_attr(dot, node_id, attr_name)
  attr_re = Regexp.escape(attr_name)

  extract_attr_block(dot, node_id).each do |block|
    value_re = /#{attr_re}\s*=\s*"((?:[^"\\]|\\.)*)"/m
    value_match = block.match(value_re)
    return dot_unescape(value_match[1]) if value_match
  end

  nil
end

# Extract node IDs with their shapes from the DOT file.
# Uses the robust block extractor so shapes are found even when the
# attribute block contains ] inside quoted strings.
def extract_nodes_with_shapes(dot)
  nodes = {}
  dot_keywords = %w[graph digraph node edge subgraph]

  # Find all node IDs that have [...] blocks
  dot.scan(/^\s*(\w+)\s*\[/m).flatten.uniq.each do |id|
    next if dot_keywords.include?(id)
    extract_attr_block(dot, id).each do |block|
      shape_match = block.match(/shape\s*=\s*(\w+)/)
      if shape_match
        nodes[id] = shape_match[1]
        break
      end
    end
    # If no shape found in any block, still record the node
    nodes[id] = nil unless nodes.key?(id)
  end
  nodes
end

nodes = extract_nodes_with_shapes(dot)
extracted = 0

nodes.each do |node_id, shape|
  case shape
  when "box"
    prompt = extract_node_attr(dot, node_id, "prompt")
    if prompt
      file_path = prompts_dir.join("#{node_id}.md")
      # Strip leading/trailing whitespace but preserve internal formatting
      File.write(file_path, prompt.strip + "\n")
      extracted += 1
      warn "Extracted prompt: #{file_path}"
    else
      warn "WARNING: box node \"#{node_id}\" has no prompt attribute"
    end

  when "hexagon"
    question = extract_node_attr(dot, node_id, "question")
    if question
      file_path = prompts_dir.join("#{node_id}.md")
      File.write(file_path, question.strip + "\n")
      extracted += 1
      warn "Extracted question: #{file_path}"
    else
      warn "WARNING: hexagon node \"#{node_id}\" has no question attribute"
    end
  end
end

warn "\nDone: extracted #{extracted} prompt(s) to #{prompts_dir}"
