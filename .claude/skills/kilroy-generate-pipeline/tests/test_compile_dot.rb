#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "tempfile"
require "fileutils"
require "yaml"
require "digest"

class TestCompileDot < Minitest::Test
  SCRIPT = File.join(__dir__, "../script", "compile_dot.rb")

  def setup
    @tmpdir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def write_yaml(content)
    path = File.join(@tmpdir, "pipeline-test-config.yaml")
    File.write(path, content)
    path
  end

  def write_prompt(target, node_id, content)
    dir = File.join(@tmpdir, "prompts")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "#{node_id}.md")
    File.write(path, content)
    path
  end

  def minimal_yaml
    <<~YAML
      target: mytest
      repo_path: .
      output_dot: pipeline-test.dot
      graph_id: test_pipeline
      graph_goal: "A test pipeline"
      default_max_retry: 3
      retry_target: implement
      fallback_retry_target: human_gate
      nodes:
        - id: start
          shape: Mdiamond
        - id: exit
          shape: Msquare
        - id: implement
          shape: box
          class: hard
        - id: check_implement
          shape: diamond
        - id: verify_build
          shape: parallelogram
        - id: check_build
          shape: diamond
        - id: human_gate
          shape: hexagon
          choices: "[R] Retry;[A] Abort"
      edges:
        - from: start
          to: implement
        - from: implement
          to: check_implement
        - from: check_implement
          to: verify_build
          condition: "outcome = success"
        - from: check_implement
          to: human_gate
          condition: "outcome = fail"
        - from: check_implement
          to: human_gate
        - from: verify_build
          to: check_build
        - from: check_build
          to: exit
          condition: "outcome = success"
        - from: check_build
          to: implement
          condition: "outcome = fail"
          loop_restart: true
        - from: check_build
          to: human_gate
        - from: human_gate
          to: implement
          condition: "choice = 0"
        - from: human_gate
          to: exit
          condition: "choice = 1"
        - from: human_gate
          to: exit
      required_gates:
        - id: verify_build
          tool_command: "cargo build --release"
          timeout: "120s"
      model_stylesheet: |
        * { llm_model: claude-sonnet-4-6; }
    YAML
  end

  def test_no_args_exits_1
    out = `ruby #{SCRIPT} 2>&1`
    assert_equal 1, $?.exitstatus
    assert_includes out, "Usage"
  end

  def test_compiles_minimal_pipeline
    yaml_path = write_yaml(minimal_yaml)
    write_prompt("mytest", "implement", "Do the implementation.")
    write_prompt("mytest", "human_gate", "Pipeline needs help.")

    out_path = File.join(@tmpdir, "output.dot")
    err = `ruby #{SCRIPT} #{yaml_path} #{out_path} 2>&1`
    assert_equal 0, $?.exitstatus, "compile_dot.rb failed: #{err}"
    assert File.exist?(out_path)

    dot = File.read(out_path)
    assert_includes dot, "digraph test_pipeline {"
    assert_includes dot, 'goal="A test pipeline"'
    assert_includes dot, "rankdir=LR"
    assert_includes dot, "default_max_retry=3"
    assert_includes dot, 'retry_target="implement"'
    assert_includes dot, 'fallback_retry_target="human_gate"'
    assert_includes dot, "start [shape=Mdiamond]"
    assert_includes dot, "exit [shape=Msquare]"
    assert_includes dot, 'implement [shape=box, class="hard", prompt="Do the implementation."]'
    assert_includes dot, "check_implement [shape=diamond]"
    assert_includes dot, 'verify_build [shape=parallelogram, tool_command="cargo build --release", timeout="120s"]'
    assert_includes dot, "check_build [shape=diamond]"
    assert_includes dot, 'human_gate [shape=hexagon, question="Pipeline needs help."'
    assert_includes dot, 'choices="[R] Retry;[A] Abort"'
    assert_includes dot, "start -> implement"
    assert_includes dot, 'check_implement -> verify_build [condition="outcome = success"]'
    assert_includes dot, 'check_build -> implement [condition="outcome = fail", loop_restart=true]'
    assert_includes dot, "human_gate -> exit\n"
    assert dot.end_with?("\n"), "Output should end with newline"
  end

  def test_deterministic_output
    yaml_path = write_yaml(minimal_yaml)
    write_prompt("mytest", "implement", "Do the implementation.")
    write_prompt("mytest", "human_gate", "Pipeline needs help.")

    out1 = File.join(@tmpdir, "out1.dot")
    out2 = File.join(@tmpdir, "out2.dot")

    `ruby #{SCRIPT} #{yaml_path} #{out1} 2>&1`
    `ruby #{SCRIPT} #{yaml_path} #{out2} 2>&1`

    assert_equal File.read(out1), File.read(out2), "Two compilations of same input must produce identical output"
  end

  def test_config_sha256_matches
    yaml_path = write_yaml(minimal_yaml)
    write_prompt("mytest", "implement", "Do the implementation.")
    write_prompt("mytest", "human_gate", "Pipeline needs help.")

    out_path = File.join(@tmpdir, "output.dot")
    `ruby #{SCRIPT} #{yaml_path} #{out_path} 2>&1`

    expected_sha = Digest::SHA256.hexdigest(File.read(yaml_path))
    dot = File.read(out_path)
    assert_includes dot, "config_sha256=\"#{expected_sha}\""
  end

  def test_missing_prompt_file_exits_1
    yaml_path = write_yaml(minimal_yaml)
    # Don't create any prompt files

    out_path = File.join(@tmpdir, "output.dot")
    err = `ruby #{SCRIPT} #{yaml_path} #{out_path} 2>&1`
    assert_equal 1, $?.exitstatus
    assert_includes err, "Prompt file not found"
  end

  def test_escapes_quotes_in_prompts
    yaml = <<~YAML
      target: mytest
      repo_path: .
      output_dot: pipeline-test.dot
      graph_id: test_pipeline
      graph_goal: "Test"
      nodes:
        - id: start
          shape: Mdiamond
        - id: implement
          shape: box
        - id: exit
          shape: Msquare
      edges:
        - from: start
          to: implement
        - from: implement
          to: exit
      model_stylesheet: |
        * { llm_model: claude-sonnet-4-6; }
    YAML

    yaml_path = write_yaml(yaml)
    write_prompt("mytest", "implement", 'Use syntax = "proto3";')

    out_path = File.join(@tmpdir, "output.dot")
    `ruby #{SCRIPT} #{yaml_path} #{out_path} 2>&1`
    assert_equal 0, $?.exitstatus

    dot = File.read(out_path)
    assert_includes dot, 'syntax = \\"proto3\\";'
  end

  def test_gate_with_max_retries
    yaml = <<~YAML
      target: mytest
      repo_path: .
      output_dot: pipeline-test.dot
      graph_id: test_pipeline
      graph_goal: "Test"
      nodes:
        - id: start
          shape: Mdiamond
        - id: fix_fmt
          shape: parallelogram
        - id: exit
          shape: Msquare
      edges:
        - from: start
          to: fix_fmt
        - from: fix_fmt
          to: exit
      required_gates:
        - id: fix_fmt
          tool_command: "cargo fmt --all"
          max_retries: 0
      model_stylesheet: |
        * { llm_model: claude-sonnet-4-6; }
    YAML

    yaml_path = write_yaml(yaml)
    out_path = File.join(@tmpdir, "output.dot")

    `ruby #{SCRIPT} #{yaml_path} #{out_path} 2>&1`
    assert_equal 0, $?.exitstatus

    dot = File.read(out_path)
    assert_includes dot, "fix_fmt [shape=parallelogram, max_retries=0"
    assert_includes dot, 'tool_command="cargo fmt --all"'
  end

  def test_goal_gate_attribute
    yaml = <<~YAML
      target: mytest
      repo_path: .
      output_dot: pipeline-test.dot
      graph_id: test_pipeline
      graph_goal: "Test"
      nodes:
        - id: start
          shape: Mdiamond
        - id: review
          shape: box
          class: verify
          goal_gate: true
        - id: exit
          shape: Msquare
      edges:
        - from: start
          to: review
        - from: review
          to: exit
      model_stylesheet: |
        * { llm_model: claude-sonnet-4-6; }
    YAML

    yaml_path = write_yaml(yaml)
    write_prompt("mytest", "review", "Review the code.")

    out_path = File.join(@tmpdir, "output.dot")
    `ruby #{SCRIPT} #{yaml_path} #{out_path} 2>&1`
    assert_equal 0, $?.exitstatus

    dot = File.read(out_path)
    assert_includes dot, 'review [shape=box, class="verify", goal_gate=true, prompt="Review the code."]'
  end

  def test_writes_to_stdout_when_no_output_path
    yaml_path = write_yaml(minimal_yaml)
    write_prompt("mytest", "implement", "Do stuff.")
    write_prompt("mytest", "human_gate", "Need help.")

    out = `ruby #{SCRIPT} #{yaml_path} 2>/dev/null`
    assert_equal 0, $?.exitstatus
    assert_includes out, "digraph test_pipeline {"
  end

  def test_edge_with_label
    yaml = <<~YAML
      target: mytest
      repo_path: .
      output_dot: pipeline-test.dot
      graph_id: test_pipeline
      graph_goal: "Test"
      nodes:
        - id: start
          shape: Mdiamond
        - id: gate
          shape: hexagon
          options: "Retry,Abort"
        - id: work
          shape: box
        - id: exit
          shape: Msquare
      edges:
        - from: start
          to: gate
        - from: gate
          to: work
          label: "Retry"
        - from: gate
          to: exit
          label: "Abort"
      model_stylesheet: |
        * { llm_model: claude-sonnet-4-6; }
    YAML

    yaml_path = write_yaml(yaml)
    write_prompt("mytest", "gate", "Choose action.")
    write_prompt("mytest", "work", "Do work.")

    out_path = File.join(@tmpdir, "output.dot")
    `ruby #{SCRIPT} #{yaml_path} #{out_path} 2>&1`
    assert_equal 0, $?.exitstatus

    dot = File.read(out_path)
    assert_includes dot, 'gate -> work [label="Retry"]'
    assert_includes dot, 'gate -> exit [label="Abort"]'
  end

  def test_missing_target_exits_1
    yaml = write_yaml(<<~YAML)
      repo_path: .
      output_dot: test.dot
      graph_id: test
    YAML

    out = `ruby #{SCRIPT} #{yaml} 2>&1`
    assert_equal 1, $?.exitstatus
    assert_includes out, "missing 'target'"
  end
end
