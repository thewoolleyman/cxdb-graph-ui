#!/usr/bin/env ruby
# frozen_string_literal: true

# Orchestrates the full pipeline generation flow for a target.
#
# Two operating modes:
#
# 1. COMPILE MODE (default): When a config YAML exists with edges and nodes,
#    deterministically compiles the DOT from YAML + prompt files. No LLM.
#    Flow: compile -> verify -> validate
#
# 2. BOOTSTRAP MODE: When no config YAML exists and no DOT file exists,
#    uses the LLM to generate an initial DOT, then extracts prompts and
#    a config skeleton.
#    Flow: render -> ingest -> patch -> extract_prompts -> verify -> validate
#
# Safety check: If a DOT file exists but no config YAML exists, refuses
# to proceed (prevents accidental overwrite of hand-edited DOT files).
#
# Usage: ruby generate_pipeline.rb [--force] <target>
# Target: "." (this repo)
#
# Skips compilation if the config YAML hasn't changed since the DOT was last
# generated (checksum match). Use --force to recompile unconditionally.

require "yaml"
require "pathname"
require "digest"
require "open3"

SCRIPT_DIR = Pathname.new(__dir__).realpath
REPO_ROOT = Pathname.new(ENV.fetch("REPO_ROOT", SCRIPT_DIR.join("../../../..").to_s)).realpath
KILROY_BIN = ENV.fetch("KILROY_BIN", REPO_ROOT.join("../kilroy/kilroy").to_s)
TARGETS = %w[.].freeze

COMPILE_STEPS = %i[compile verify validate].freeze
BOOTSTRAP_STEPS = %i[render ingest patch extract_prompts verify validate].freeze

def usage
  warn <<~USAGE
    Usage: generate_pipeline.rb [--force] <target>

    Target: . (this repo)

    Modes:
      COMPILE (default) — deterministic DOT from YAML config + prompt files.
        No LLM. Same input always produces byte-identical output.

      BOOTSTRAP — when no config YAML exists. Uses LLM to generate initial
        DOT, then extracts prompts alongside the config YAML.
        Requires: kilroy binary, CXDB running, ANTHROPIC_API_KEY.

    Options:
      --force    Recompile even if config YAML hasn't changed (checksum match).

    Safety:
      Refuses to proceed if a DOT file exists but no config YAML exists.
      This prevents accidental overwrite of hand-edited DOT files.
  USAGE
  exit 1
end

# Tracks step outcomes for the summary.
class StepTracker
  attr_reader :results, :steps

  def initialize(target, steps)
    @target = target
    @steps = steps
    @results = {}
  end

  def record(step, success, detail = nil)
    @results[step] = { success: success, detail: detail }
  end

  def failed?
    @results.any? { |_, v| !v[:success] }
  end

  def failed_step
    @results.find { |_, v| !v[:success] }&.first
  end

  def format_summary
    lines = []
    lines << ""
    lines << "=" * 60
    lines << "SUMMARY: #{@target}"
    lines << "=" * 60

    @steps.each do |step|
      r = @results[step]
      if r.nil?
        lines << "  #{step}: SKIPPED"
      elsif r[:success]
        detail = r[:detail] ? " -- #{r[:detail]}" : ""
        lines << "  #{step}: OK#{detail}"
      else
        lines << "  #{step}: FAILED"
        lines << "    #{r[:detail]}" if r[:detail]
      end
    end

    if failed?
      lines << ""
      lines << "ACTION PLAN:"
      case failed_step
      when :compile
        lines << "  - compile_dot.rb failed. Check that:"
        lines << "    - All prompt files exist in factory/prompts/"
        lines << "    - YAML config has valid nodes and edges"
        lines << "  - Run manually: ruby #{SCRIPT_DIR}/compile_dot.rb pipeline-config.yaml"
      when :render
        lines << "  - Check that the YAML config file exists and is valid YAML."
        lines << "  - Run: ruby #{SCRIPT_DIR}/render_prompt.rb pipeline-config.yaml"
      when :ingest
        lines << "  - kilroy attractor ingest failed. Common causes:"
        lines << "    - Hit max turns (increase with KILROY_INGEST_MAX_TURNS=50)"
        lines << "    - CXDB not running (check: curl -sf http://localhost:9110/healthz)"
        lines << "    - ANTHROPIC_API_KEY not set (check via direnv)"
        lines << "  - Re-run the generation."
      when :patch
        lines << "  - patch_dot.rb failed. The DOT file may have unexpected structure."
        lines << "  - Run manually: ruby #{SCRIPT_DIR}/patch_dot.rb pipeline-config.yaml <dot-file>"
      when :extract_prompts
        lines << "  - extract_prompts.rb failed. The DOT file may have unexpected format."
        lines << "  - Run manually: ruby #{SCRIPT_DIR}/extract_prompts.rb pipeline-config.yaml <dot-file>"
      when :verify
        lines << "  - Verification found mismatches between YAML and DOT."
        lines << "  - Run verify manually for details:"
        lines << "    ruby #{SCRIPT_DIR}/verify_dot.rb pipeline-config.yaml <dot-file>"
      when :validate
        lines << "  - kilroy attractor validate found structural issues in the DOT."
        lines << "  - Inspect the DOT file for syntax errors or invalid attributes."
      end
    end

    lines << "=" * 60
    lines << ""
    lines.join("\n")
  end

  def print_summary
    puts format_summary
  end
end

# Captures output from a command. Returns [success, combined_output].
def capture_cmd(description, *args, env: {})
  full_env = ENV.to_h.merge(env).tap { |e| e.delete("CLAUDECODE") }
  output = "[cmd] #{description}\n"
  stdout_str, stderr_str, status = Open3.capture3(full_env, *args)
  output += stdout_str unless stdout_str.empty?
  output += stderr_str unless stderr_str.empty?
  [status.success?, output]
end

# Runs a command, printing output directly. Returns success boolean.
def run_cmd(description, *args, env: {})
  puts description
  full_env = ENV.to_h.merge(env).tap { |e| e.delete("CLAUDECODE") }
  system(full_env, *args)
  $?.success?
end

# Compute SHA-256 of a file's contents.
def file_sha256(path)
  Digest::SHA256.hexdigest(File.read(path))
end

# Read the config_sha256 attribute from a DOT file's graph attributes.
def read_dot_checksum(dot_file)
  return nil unless File.exist?(dot_file)

  content = File.read(dot_file)
  match = content.match(/config_sha256\s*=\s*"([a-f0-9]{64})"/)
  match ? match[1] : nil
end

# Determine operating mode for a target.
# Returns :compile, :bootstrap, or :safety_error
def determine_mode(yaml_file, dot_file)
  yaml_exists = File.exist?(yaml_file)
  dot_exists = File.exist?(dot_file)

  if yaml_exists
    :compile
  elsif !yaml_exists && !dot_exists
    :bootstrap
  else
    # DOT exists but no config YAML — safety check
    :safety_error
  end
end

# Check if a config YAML has the fields needed for compile mode.
def config_has_compile_fields?(yaml_file)
  doc = YAML.safe_load(File.read(yaml_file), permitted_classes: [Symbol])
  !doc["edges"].nil? && !doc["nodes"].nil? && !(doc["nodes"] || []).empty?
end

# --- COMPILE MODE ---

def run_compile_mode(target, yaml_file, dot_file, force:, buffered: false)
  output_lines = []
  log = ->(msg) { buffered ? output_lines << msg : puts(msg) }
  run = if buffered
          ->(desc, *args, **kwargs) {
            ok, out = capture_cmd(desc, *args, **kwargs)
            output_lines << out
            ok
          }
        else
          ->(desc, *args, **kwargs) { run_cmd(desc, *args, **kwargs) }
        end

  doc = YAML.safe_load(File.read(yaml_file), permitted_classes: [Symbol])
  output_dot = doc["output_dot"]
  tracker = StepTracker.new(target, COMPILE_STEPS)

  # Checksum-based skip
  yaml_checksum = file_sha256(yaml_file)
  dot_checksum = read_dot_checksum(dot_file)

  if !force && dot_checksum == yaml_checksum
    log.call "Config YAML unchanged (sha256=#{yaml_checksum[0..11]}...). Skipping compilation, running verify/validate only."
  else
    if force
      log.call "Force mode: recompiling ..."
    elsif dot_checksum.nil?
      log.call "No existing checksum in DOT. Compiling ..."
    else
      log.call "Config YAML changed (#{dot_checksum[0..11]}... -> #{yaml_checksum[0..11]}...). Recompiling ..."
    end

    # Step 1: Compile
    ok = run.call(
      "Compiling DOT file ...",
      "ruby", SCRIPT_DIR.join("compile_dot.rb").to_s, yaml_file, dot_file
    )
    if ok
      tracker.record(:compile, true)
    else
      tracker.record(:compile, false, "compile_dot.rb exited with error")
      output_lines << tracker.format_summary if buffered
      tracker.print_summary unless buffered
      return buffered ? [false, output_lines.join("\n")] : false
    end
  end

  # Step 2: Verify
  ok = run.call(
    "Verifying DOT file ...",
    "ruby", SCRIPT_DIR.join("verify_dot.rb").to_s, yaml_file, dot_file
  )
  if ok
    gate_ids = (doc["required_gates"] || []).map { |g| g["id"] }.join(", ")
    tracker.record(:verify, true, "gates: #{gate_ids}")
  else
    tracker.record(:verify, false, "verify_dot.rb found mismatches")
  end

  # Step 3: Validate with kilroy
  ok = run.call(
    "Validating with kilroy attractor validate ...",
    KILROY_BIN, "attractor", "validate", "--graph", dot_file,
    env: {}
  )
  if ok
    tracker.record(:validate, true)
  else
    tracker.record(:validate, false, "kilroy attractor validate found issues")
  end

  output_lines << tracker.format_summary if buffered
  tracker.print_summary unless buffered

  success = !tracker.failed?
  if success
    log.call "=== Done: #{target} (compile mode) ==="
  else
    log.call "=== FAILED: #{target} ==="
  end

  buffered ? [success, output_lines.join("\n")] : success
end

# --- BOOTSTRAP MODE ---

def run_bootstrap_mode(target, yaml_file, dot_file, force:, buffered: false)
  output_lines = []
  log = ->(msg) { buffered ? output_lines << msg : puts(msg) }
  run = if buffered
          ->(desc, *args, **kwargs) {
            ok, out = capture_cmd(desc, *args, **kwargs)
            output_lines << out
            ok
          }
        else
          ->(desc, *args, **kwargs) { run_cmd(desc, *args, **kwargs) }
        end

  tracker = StepTracker.new(target, BOOTSTRAP_STEPS)
  log.call "BOOTSTRAP MODE: No config YAML found. Using LLM to generate initial pipeline."
  log.call "NOTE: After bootstrap, you must manually create the config YAML with edges."
  log.call "      The generated DOT and extracted prompts are a starting point."

  # For bootstrap, we need a minimal YAML with at least a goal
  # Since there's no config, we can't proceed without one
  log.call "ERROR: Bootstrap mode requires a config YAML file."
  log.call "Create #{yaml_file} with at least: target, repo_path, output_dot, goal, rules, required_gates."
  tracker.record(:render, false, "Config YAML not found — bootstrap requires initial config")
  output_lines << tracker.format_summary if buffered
  tracker.print_summary unless buffered
  return buffered ? [false, output_lines.join("\n")] : false
end

# --- MAIN ENTRY POINT ---

def run_one(target, force:, buffered: false)
  output_lines = []
  log = ->(msg) { buffered ? output_lines << msg : puts(msg) }

  yaml_file = REPO_ROOT.join("factory", "pipeline-config.yaml").to_s
  doc = File.exist?(yaml_file) ? YAML.safe_load(File.read(yaml_file), permitted_classes: [Symbol]) : nil
  output_dot = doc ? doc["output_dot"] : "pipeline.dot"
  dot_file = REPO_ROOT.join(output_dot).to_s

  mode = determine_mode(yaml_file, dot_file)
  log.call "=== Generating pipeline for: #{target} (mode: #{mode}) ==="

  case mode
  when :safety_error
    log.call "ERROR: #{dot_file} exists but #{yaml_file} does not."
    log.call "This is a safety check to prevent accidental overwrite of existing DOT files."
    log.call ""
    log.call "To proceed, either:"
    log.call "  1. Create a config YAML: #{yaml_file}"
    log.call "  2. Delete the existing DOT file if it's no longer needed: rm #{dot_file}"
    tracker = StepTracker.new(target, COMPILE_STEPS)
    tracker.record(:compile, false, "DOT exists without config YAML (safety check)")
    output_lines << tracker.format_summary if buffered
    tracker.print_summary unless buffered
    return buffered ? [false, output_lines.join("\n")] : false

  when :compile
    # Check if config has compile fields (edges, nodes)
    if config_has_compile_fields?(yaml_file)
      return run_compile_mode(target, yaml_file, dot_file, force: force, buffered: buffered)
    else
      # Legacy mode: config exists but no edges/nodes — use old LLM flow
      log.call "Config exists but lacks edges/nodes — using legacy LLM ingest flow."
      return run_legacy_mode(target, yaml_file, dot_file, force: force, buffered: buffered)
    end

  when :bootstrap
    return run_bootstrap_mode(target, yaml_file, dot_file, force: force, buffered: buffered)
  end
end

# --- LEGACY MODE (old LLM-based flow for configs without edges) ---

def run_legacy_mode(target, yaml_file, dot_file, force:, buffered: false)
  output_lines = []
  log = ->(msg) { buffered ? output_lines << msg : puts(msg) }
  run = if buffered
          ->(desc, *args, **kwargs) {
            ok, out = capture_cmd(desc, *args, **kwargs)
            output_lines << out
            ok
          }
        else
          ->(desc, *args, **kwargs) { run_cmd(desc, *args, **kwargs) }
        end

  steps = %i[render ingest patch verify validate]
  doc = YAML.safe_load(File.read(yaml_file), permitted_classes: [Symbol])
  repo_path = doc["repo_path"]
  output_dot = doc["output_dot"]
  tracker = StepTracker.new(target, steps)

  # Resolve repo_path relative to REPO_ROOT
  repo_path = if repo_path == "."
                REPO_ROOT.to_s
              elsif !repo_path.start_with?("/")
                REPO_ROOT.join(repo_path).to_s
              else
                repo_path
              end

  # Checksum-based skip
  yaml_checksum = file_sha256(yaml_file)
  dot_checksum = read_dot_checksum(dot_file)
  skip_ingest = false

  if force
    log.call "Force mode: deleting existing DOT file ..."
    File.delete(dot_file) if File.exist?(dot_file)
  elsif dot_checksum == yaml_checksum
    log.call "Config YAML unchanged. Skipping ingest, running patch/verify/validate only."
    skip_ingest = true
  else
    log.call "Running full LLM ingest ..."
  end

  unless skip_ingest
    # Step 1: Render prompt
    log.call "Rendering ingest prompt ..."
    prompt = `ruby #{SCRIPT_DIR.join("render_prompt.rb")} #{yaml_file}`
    unless $?.success?
      tracker.record(:render, false, "render_prompt.rb exited with #{$?.exitstatus}")
      output_lines << tracker.format_summary if buffered
      tracker.print_summary unless buffered
      return buffered ? [false, output_lines.join("\n")] : false
    end
    tracker.record(:render, true)

    # Step 2: LLM ingest
    max_turns = ENV.fetch("KILROY_INGEST_MAX_TURNS", "30")
    ok = run.call(
      "Running kilroy attractor ingest (max_turns=#{max_turns}) ...",
      "direnv", "exec", REPO_ROOT.to_s,
      KILROY_BIN, "attractor", "ingest",
      "--repo", repo_path,
      "--max-turns", max_turns,
      "-o", dot_file,
      prompt
    )
    unless ok
      tracker.record(:ingest, false, "kilroy attractor ingest exited with error")
      output_lines << tracker.format_summary if buffered
      tracker.print_summary unless buffered
      return buffered ? [false, output_lines.join("\n")] : false
    end
    tracker.record(:ingest, true)
  end

  # Step 3: Patch
  ok = run.call(
    "Patching DOT file ...",
    "ruby", SCRIPT_DIR.join("patch_dot.rb").to_s, yaml_file, dot_file
  )
  if ok
    tracker.record(:patch, true)
  else
    tracker.record(:patch, false, "patch_dot.rb exited with error")
    output_lines << tracker.format_summary if buffered
    tracker.print_summary unless buffered
    return buffered ? [false, output_lines.join("\n")] : false
  end

  # Step 4: Verify
  ok = run.call(
    "Verifying DOT file ...",
    "ruby", SCRIPT_DIR.join("verify_dot.rb").to_s, yaml_file, dot_file
  )
  if ok
    gate_ids = (doc["required_gates"] || []).map { |g| g["id"] }.join(", ")
    tracker.record(:verify, true, "gates: #{gate_ids}")
  else
    tracker.record(:verify, false, "verify_dot.rb found mismatches")
  end

  # Step 5: Validate
  ok = run.call(
    "Validating with kilroy attractor validate ...",
    KILROY_BIN, "attractor", "validate", "--graph", dot_file,
    env: {}
  )
  if ok
    tracker.record(:validate, true)
  else
    tracker.record(:validate, false, "kilroy attractor validate found issues")
  end

  # Write checksum on success
  unless tracker.failed?
    content = File.read(dot_file)
    if content.match?(/config_sha256\s*=\s*"[a-f0-9]{64}"/)
      content.sub!(/config_sha256\s*=\s*"[a-f0-9]{64}"/, "config_sha256=\"#{yaml_checksum}\"")
    else
      content.sub!(/^(\s*graph\s*\[)/) { "#{$1}\n    config_sha256=\"#{yaml_checksum}\"," }
    end
    File.write(dot_file, content)
    log.call "Wrote config_sha256=#{yaml_checksum[0..11]}... into #{output_dot}"
  end

  output_lines << tracker.format_summary if buffered
  tracker.print_summary unless buffered

  success = !tracker.failed?
  log.call success ? "=== Done: #{target} (legacy mode) ===" : "=== FAILED: #{target} ==="
  buffered ? [success, output_lines.join("\n")] : success
end

# Run all targets in parallel.
def run_all_parallel(force:)
  puts "Running #{TARGETS.length} targets in parallel: #{TARGETS.join(", ")}"
  puts ""

  threads = TARGETS.map do |t|
    [t, Thread.new { run_one(t, force: force, buffered: true) }]
  end

  thread_results = threads.map do |target, thread|
    success, output = thread.value
    { target: target, success: success, output: output }
  end

  successes = thread_results.select { |r| r[:success] }
  failures = thread_results.reject { |r| r[:success] }

  unless successes.empty?
    puts "#{"=" * 60}"
    puts "SUCCEEDED: #{successes.map { |r| r[:target] }.join(", ")}"
    puts "#{"=" * 60}"
    successes.each do |r|
      puts ""
      puts "-" * 60
      puts "#{r[:target]} (success)"
      puts "-" * 60
      puts r[:output]
    end
  end

  unless failures.empty?
    puts ""
    puts "#{"=" * 60}"
    puts "FAILED: #{failures.map { |r| r[:target] }.join(", ")}"
    puts "#{"=" * 60}"
    failures.each do |r|
      puts ""
      puts "-" * 60
      puts "#{r[:target]} (FAILED) — full output below"
      puts "-" * 60
      puts r[:output]
    end
  end

  puts ""
  puts "#{"=" * 60}"
  puts "PARALLEL RUN COMPLETE"
  puts "  Succeeded: #{successes.map { |r| r[:target] }.join(", ").then { |s| s.empty? ? "(none)" : s }}"
  puts "  Failed:    #{failures.map { |r| r[:target] }.join(", ").then { |s| s.empty? ? "(none)" : s }}"
  puts "#{"=" * 60}"

  failures.empty?
end

# --- Main ---

force = ARGV.delete("--force")
target = ARGV[0]
usage if target.nil? || target.empty?

if target == "all"
  success = run_all_parallel(force: !!force)
  exit(success ? 0 : 1)
elsif TARGETS.include?(target)
  success = run_one(target, force: !!force)
  exit(success ? 0 : 1)
else
  warn "ERROR: unknown target '#{target}'"
  usage
end
