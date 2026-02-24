#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "tempfile"
require "yaml"

class TestPatchDot < Minitest::Test
  SCRIPT = File.join(__dir__, "../script", "patch_dot.rb")

  SAMPLE_DOT = <<~DOT
    digraph test {
      graph [
        goal="test goal",
        model_stylesheet="
          * { llm_model: old-model; llm_provider: anthropic; max_tokens: 1024; }
        "
      ]

      start [shape=Mdiamond]
      exit [shape=Msquare]

      expand_spec [
        shape=box,
        prompt="Old expand spec prompt."
      ]

      verify_build [
        shape=parallelogram,
        tool_command="old build command"
      ]

      verify_test [
        shape=parallelogram,
        tool_command="old test command"
      ]

      start -> expand_spec
      expand_spec -> verify_build
      verify_build -> verify_test
      verify_test -> exit
    }
  DOT

  SAMPLE_CONFIG = {
    "required_gates" => [
      {"id" => "verify_build", "tool_command" => "cargo build --release"},
      {"id" => "verify_test", "tool_command" => "cargo test --all"}
    ],
    "expand_spec_prompt" => "New expand spec prompt.\nWith multiple lines.",
    "model_stylesheet" => "* { llm_model: claude-sonnet-4-6; llm_provider: anthropic; max_tokens: 65536; }"
  }

  def with_files(config_data, dot_content)
    yaml_f = Tempfile.new(["config", ".yaml"])
    yaml_f.write(YAML.dump(config_data))
    yaml_f.close

    dot_f = Tempfile.new(["pipeline", ".dot"])
    dot_f.write(dot_content)
    dot_f.close

    yield yaml_f.path, dot_f.path
  ensure
    yaml_f&.unlink
    dot_f&.unlink
  end

  def run_script(yaml_path, dot_path)
    out = `ruby #{SCRIPT} #{yaml_path} #{dot_path} 2>&1`
    [out, $?.exitstatus]
  end

  def test_patches_tool_commands
    with_files(SAMPLE_CONFIG, SAMPLE_DOT) do |yaml_path, dot_path|
      out, status = run_script(yaml_path, dot_path)
      assert_equal 0, status

      dot = File.read(dot_path)
      assert_includes dot, 'tool_command="cargo build --release"'
      assert_includes dot, 'tool_command="cargo test --all"'
      refute_includes dot, "old build command"
      refute_includes dot, "old test command"
    end
  end

  def test_patches_expand_spec_prompt
    with_files(SAMPLE_CONFIG, SAMPLE_DOT) do |yaml_path, dot_path|
      run_script(yaml_path, dot_path)

      dot = File.read(dot_path)
      assert_includes dot, "New expand spec prompt."
      refute_includes dot, "Old expand spec prompt."
    end
  end

  def test_patches_model_stylesheet
    with_files(SAMPLE_CONFIG, SAMPLE_DOT) do |yaml_path, dot_path|
      run_script(yaml_path, dot_path)

      dot = File.read(dot_path)
      assert_includes dot, "claude-sonnet-4-6"
      refute_includes dot, "old-model"
    end
  end

  def test_warns_on_missing_node
    config = {
      "required_gates" => [
        {"id" => "nonexistent_gate", "tool_command" => "echo hi"}
      ]
    }
    with_files(config, SAMPLE_DOT) do |yaml_path, dot_path|
      out, status = run_script(yaml_path, dot_path)
      assert_equal 0, status
      assert_includes out, 'WARNING: Node "nonexistent_gate"'
    end
  end

  def test_handles_escaped_quotes_in_command
    config = {
      "required_gates" => [
        {"id" => "verify_build", "tool_command" => 'sh -c "echo hello"'}
      ]
    }
    with_files(config, SAMPLE_DOT) do |yaml_path, dot_path|
      run_script(yaml_path, dot_path)

      dot = File.read(dot_path)
      assert_includes dot, 'sh -c \\"echo hello\\"'
    end
  end

  def test_no_args_exits_1
    _out, status = run_script("", "")
    assert_equal 1, status
  end

  def test_patches_graph_id
    config = SAMPLE_CONFIG.merge("graph_id" => "my_pipeline")
    with_files(config, SAMPLE_DOT) do |yaml_path, dot_path|
      out, status = run_script(yaml_path, dot_path)
      assert_equal 0, status

      dot = File.read(dot_path)
      assert_includes dot, "digraph my_pipeline {"
      refute_includes dot, "digraph test {"
    end
  end

  def test_patches_existing_retry_target
    dot_with_retry = SAMPLE_DOT.sub(
      'goal="test goal"',
      'goal="test goal", retry_target="old_target"'
    )
    config = SAMPLE_CONFIG.merge("retry_target" => "implement")
    with_files(config, dot_with_retry) do |yaml_path, dot_path|
      out, status = run_script(yaml_path, dot_path)
      assert_equal 0, status

      dot = File.read(dot_path)
      assert_includes dot, 'retry_target="implement"'
      refute_includes dot, 'retry_target="old_target"'
    end
  end

  def test_injects_retry_target_when_absent
    config = SAMPLE_CONFIG.merge("retry_target" => "implement")
    with_files(config, SAMPLE_DOT) do |yaml_path, dot_path|
      out, status = run_script(yaml_path, dot_path)
      assert_equal 0, status

      dot = File.read(dot_path)
      assert_includes dot, 'retry_target="implement"'
    end
  end

  def test_normalizes_condition_spacing
    dot_with_conditions = <<~DOT
      digraph test {
        graph [goal="test"]
        a -> b [condition="outcome=success"]
        b -> c [condition="outcome=fail&&context.failure_class!=transient_infra"]
        c -> d [condition="context.retry_count>=3"]
      }
    DOT
    config = {}
    with_files(config, dot_with_conditions) do |yaml_path, dot_path|
      run_script(yaml_path, dot_path)

      dot = File.read(dot_path)
      assert_includes dot, 'condition="outcome = success"'
      assert_includes dot, 'condition="outcome = fail && context.failure_class != transient_infra"'
      assert_includes dot, 'condition="context.retry_count >= 3"'
    end
  end

  def test_node_inventory_warning
    config = {
      "nodes" => [
        {"id" => "start", "shape" => "Mdiamond"},
        {"id" => "missing_node", "shape" => "box"}
      ]
    }
    with_files(config, SAMPLE_DOT) do |yaml_path, dot_path|
      out, status = run_script(yaml_path, dot_path)
      assert_equal 0, status
      assert_includes out, 'WARNING: YAML node "missing_node" not found in DOT'
    end
  end
end
