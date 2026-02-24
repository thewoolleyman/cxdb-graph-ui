#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "tempfile"
require "yaml"

class TestRenderPrompt < Minitest::Test
  SCRIPT = File.join(__dir__, "../script", "render_prompt.rb")

  def with_yaml_file(data)
    f = Tempfile.new(["test", ".yaml"])
    f.write(YAML.dump(data))
    f.close
    yield f.path
  ensure
    f.unlink
  end

  def run_script(path)
    out = `ruby #{SCRIPT} #{path} 2>&1`
    [out, $?.exitstatus]
  end

  def test_renders_goal_section
    data = {
      "goal" => "Build the thing.",
      "required_gates" => [],
      "rules" => []
    }
    with_yaml_file(data) do |path|
      out, status = run_script(path)
      assert_equal 0, status
      assert_includes out, "## Goal"
      assert_includes out, "Build the thing."
    end
  end

  def test_renders_gates_with_fenced_commands
    data = {
      "goal" => "Build it.",
      "required_gates" => [
        {"id" => "verify_build", "tool_command" => "cargo build --release"},
        {"id" => "verify_test", "tool_command" => "cargo test"}
      ],
      "rules" => []
    }
    with_yaml_file(data) do |path|
      out, status = run_script(path)
      assert_equal 0, status
      assert_includes out, "## Required Tool Gates"
      assert_includes out, "### verify_build"
      assert_includes out, "```bash\ncargo build --release\n```"
      assert_includes out, "### verify_test"
    end
  end

  def test_renders_rules_section
    data = {
      "goal" => "Build it.",
      "required_gates" => [],
      "rules" => ["no fanout", "single path only"]
    }
    with_yaml_file(data) do |path|
      out, status = run_script(path)
      assert_equal 0, status
      assert_includes out, "## Rules"
      assert_includes out, "- no fanout"
      assert_includes out, "- single path only"
    end
  end

  def test_omits_empty_rules
    data = {
      "goal" => "Build it.",
      "required_gates" => [],
      "rules" => []
    }
    with_yaml_file(data) do |path|
      out, status = run_script(path)
      assert_equal 0, status
      refute_includes out, "## Rules"
    end
  end

  def test_omits_empty_gates
    data = {
      "goal" => "Build it.",
      "required_gates" => [],
      "rules" => []
    }
    with_yaml_file(data) do |path|
      out, status = run_script(path)
      assert_equal 0, status
      refute_includes out, "## Required Tool Gates"
    end
  end

  def test_no_args_exits_1
    out = `ruby #{SCRIPT} 2>&1`
    refute_equal 0, $?.exitstatus
  end

  def test_renders_structural_constraints
    data = {
      "goal" => "Build it.",
      "required_gates" => [],
      "rules" => [],
      "graph_id" => "test_pipeline",
      "topology" => "no-fanout",
      "retry_target" => "implement",
      "fallback_retry_target" => "human_gate",
      "nodes" => [
        {"id" => "start", "shape" => "Mdiamond"},
        {"id" => "implement", "shape" => "box", "class" => "hard"},
        {"id" => "exit", "shape" => "Msquare"}
      ]
    }
    with_yaml_file(data) do |path|
      out, status = run_script(path)
      assert_equal 0, status
      assert_includes out, "## Structural Constraints"
      assert_includes out, "`test_pipeline`"
      assert_includes out, "`no-fanout`"
      assert_includes out, "`implement`"
      assert_includes out, "`human_gate`"
      assert_includes out, "### Node Inventory"
      assert_includes out, "| `start` | Mdiamond |"
      assert_includes out, "| `implement` | box | hard |"
    end
  end

  def test_renders_prompt_authoring_directive
    data = {
      "goal" => "Build it.",
      "required_gates" => [],
      "rules" => [],
      "graph_id" => "test_pipeline"
    }
    with_yaml_file(data) do |path|
      out, status = run_script(path)
      assert_equal 0, status
      assert_includes out, "### Prompt Authoring Directive"
      assert_includes out, "30-50 lines"
    end
  end

  def test_omits_structural_constraints_when_absent
    data = {
      "goal" => "Build it.",
      "required_gates" => [],
      "rules" => []
    }
    with_yaml_file(data) do |path|
      out, status = run_script(path)
      assert_equal 0, status
      refute_includes out, "## Structural Constraints"
      refute_includes out, "### Node Inventory"
    end
  end
end
