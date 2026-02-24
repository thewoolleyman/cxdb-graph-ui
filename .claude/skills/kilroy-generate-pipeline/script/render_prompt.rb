#!/usr/bin/env ruby
# frozen_string_literal: true

# Render a YAML config file into a markdown ingest prompt for kilroy attractor ingest.
# Usage: ruby render_prompt.rb <yaml-file>

require "yaml"

yaml_path = ARGV[0]
if yaml_path.nil?
  warn "Usage: render_prompt.rb <yaml-file>"
  exit 1
end

doc = YAML.safe_load(File.read(yaml_path), permitted_classes: [Symbol])

lines = []

# Goal section
lines << "## Goal\n"
lines << doc["goal"].strip
lines << ""

# Required Tool Gates section
gates = doc["required_gates"] || []
unless gates.empty?
  lines << "## Required Tool Gates\n"
  lines << "Each gate below MUST appear as a node in the DOT output with"
  lines << "exactly the node ID shown (the `### heading`), `shape=parallelogram`,"
  lines << "and the exact `tool_command` shown in the code fence.\n"
  gates.each do |gate|
    lines << "### #{gate["id"]}\n"
    lines << "```bash"
    lines << gate["tool_command"]
    lines << "```\n"
  end
end

# Rules section
rules = doc["rules"] || []
unless rules.empty?
  lines << "## Rules\n"
  rules.each { |rule| lines << "- #{rule}" }
  lines << ""
end

# Structural Constraints section (only if any structural fields present)
graph_id = doc["graph_id"]
topology = doc["topology"]
retry_target = doc["retry_target"]
fallback_retry_target = doc["fallback_retry_target"]
nodes = doc["nodes"] || []

if graph_id || topology || retry_target || fallback_retry_target || !nodes.empty?
  topology_desc = {
    "no-fanout" => "Linear pipeline with no parallel branches. Every node has at most one successor (excluding retry/error edges).",
    "full-fanout" => "Pipeline fans out to parallel branches after an initial gate, then joins before a final review.",
    "custom" => "Complex topology with application-specific routing. No automatic shape or edge constraints."
  }

  lines << "## Structural Constraints\n"
  lines << "The generated DOT file MUST conform to these structural constraints."
  lines << "Do NOT deviate from them — they are verified post-generation.\n"

  lines << "- **Graph ID:** `#{graph_id}`" if graph_id
  if topology
    desc = topology_desc[topology] || "Unknown topology."
    lines << "- **Topology:** `#{topology}` — #{desc}"
  end
  lines << "- **retry_target:** `#{retry_target}`" if retry_target
  lines << "- **fallback_retry_target:** `#{fallback_retry_target}`" if fallback_retry_target
  lines << ""

  unless nodes.empty?
    lines << "### Node Inventory\n"
    lines << "| ID | Shape | Class | Extra Attributes |"
    lines << "|---|---|---|---|"
    nodes.each do |node|
      id = node["id"]
      shape = node["shape"] || ""
      klass = node["class"] || ""
      extra = (node.keys - %w[id shape class]).map { |k| "#{k}=#{node[k]}" }.join(", ")
      lines << "| `#{id}` | #{shape} | #{klass} | #{extra} |"
    end
    lines << ""
  end

  lines << "### Prompt Authoring Directive\n"
  lines << "Use the Node Inventory above to orient your output — do NOT duplicate it."
  lines << "Each `shape=box` node prompt should be 30-50 lines of markdown."
  lines << "Every box node MUST include a Status Contract section specifying"
  lines << '`$KILROY_STAGE_STATUS_PATH` and the JSON schema `{"status":"success|fail|retry"}`.'
  lines << ""

  lines << "### Routing Directives\n"
  lines << "- Every `shape=diamond` check node MUST have edges covering `outcome=success`,"
  lines << "  `outcome=fail`, and a bare default edge."
  lines << "- Retry loops (edges with `loop_restart=true`) MUST target `#{retry_target}`." if retry_target
  lines << "- When `default_max_retry` is exhausted, route to the `#{fallback_retry_target}` node." if fallback_retry_target
  lines << "- Edge condition expressions MUST have spaces around operators:"
  lines << '  `outcome = success`, `context.retry_count >= 3`, `context.failure_class != transient_infra`.'
  lines << "- Use `&&` (with spaces) for compound conditions: `outcome = fail && context.failure_class = transient_infra`."
  lines << ""
end

puts lines.join("\n")
