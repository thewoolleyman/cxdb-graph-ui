#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "tempfile"
require "yaml"

class TestVerifyDot < Minitest::Test
  SCRIPT = File.join(__dir__, "../script", "verify_dot.rb")

  def make_dot(gates:, expand_spec_prompt: "Read the spec.", stylesheet: "* { llm_model: claude-sonnet-4-6; }")
    gate_nodes = gates.map do |g|
      <<~NODE
        #{g["id"]} [
          shape=parallelogram,
          tool_command="#{g["tool_command"]}"
        ]
      NODE
    end.join("\n")

    <<~DOT
      digraph test {
        graph [
          goal="test",
          model_stylesheet="
            #{stylesheet}
          "
        ]

        start [shape=Mdiamond]
        exit [shape=Msquare]

        expand_spec [
          shape=box,
          prompt="#{expand_spec_prompt}"
        ]

        #{gate_nodes}

        start -> expand_spec
        expand_spec -> exit
      }
    DOT
  end

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

  def test_pass_when_all_match
    gates = [
      {"id" => "verify_build", "tool_command" => "cargo build"},
      {"id" => "verify_test", "tool_command" => "cargo test"}
    ]
    config = {
      "required_gates" => gates,
      "expand_spec_prompt" => "Read the spec.",
      "model_stylesheet" => "* { llm_model: claude-sonnet-4-6; }"
    }
    dot = make_dot(gates: gates)

    with_files(config, dot) do |yaml_path, dot_path|
      out, status = run_script(yaml_path, dot_path)
      assert_equal 0, status
      assert_includes out, "PASS"
      assert_includes out, "verify_build"
      assert_includes out, "verify_test"
    end
  end

  def test_fail_on_missing_gate_node
    config = {
      "required_gates" => [
        {"id" => "verify_build", "tool_command" => "cargo build"},
        {"id" => "missing_gate", "tool_command" => "echo hi"}
      ],
      "expand_spec_prompt" => "Read the spec.",
      "model_stylesheet" => "* { llm_model: claude-sonnet-4-6; }"
    }
    gates = [{"id" => "verify_build", "tool_command" => "cargo build"}]
    dot = make_dot(gates: gates)

    with_files(config, dot) do |yaml_path, dot_path|
      out, status = run_script(yaml_path, dot_path)
      assert_equal 1, status
      assert_includes out, "MISSING NODE"
      assert_includes out, "missing_gate"
    end
  end

  def test_fail_on_tool_command_mismatch
    config = {
      "required_gates" => [
        {"id" => "verify_build", "tool_command" => "cargo build --release"}
      ],
      "expand_spec_prompt" => "Read the spec.",
      "model_stylesheet" => "* { llm_model: claude-sonnet-4-6; }"
    }
    gates = [{"id" => "verify_build", "tool_command" => "cargo build --debug"}]
    dot = make_dot(gates: gates)

    with_files(config, dot) do |yaml_path, dot_path|
      out, status = run_script(yaml_path, dot_path)
      assert_equal 1, status
      assert_includes out, "MISMATCH tool_command"
    end
  end

  def test_fail_on_stylesheet_mismatch
    config = {
      "required_gates" => [],
      "expand_spec_prompt" => "Read the spec.",
      "model_stylesheet" => "* { llm_model: claude-opus-4-6; }"
    }
    dot = make_dot(gates: [], stylesheet: "* { llm_model: claude-sonnet-4-6; }")

    with_files(config, dot) do |yaml_path, dot_path|
      out, status = run_script(yaml_path, dot_path)
      assert_equal 1, status
      assert_includes out, "MISMATCH model_stylesheet"
    end
  end

  def test_fail_on_expand_spec_mismatch
    config = {
      "required_gates" => [],
      "expand_spec_prompt" => "Read all the specs.",
      "model_stylesheet" => "* { llm_model: claude-sonnet-4-6; }"
    }
    dot = make_dot(gates: [], expand_spec_prompt: "Read only some specs.")

    with_files(config, dot) do |yaml_path, dot_path|
      out, status = run_script(yaml_path, dot_path)
      assert_equal 1, status
      assert_includes out, "MISMATCH expand_spec"
    end
  end

  def test_whitespace_normalized_comparison
    config = {
      "required_gates" => [
        {"id" => "verify_build", "tool_command" => "cargo  build   --release"}
      ],
      "expand_spec_prompt" => "Read the spec.",
      "model_stylesheet" => "* { llm_model: claude-sonnet-4-6; }"
    }
    # DOT has different whitespace but same tokens
    gates = [{"id" => "verify_build", "tool_command" => "cargo build --release"}]
    dot = make_dot(gates: gates)

    with_files(config, dot) do |yaml_path, dot_path|
      out, status = run_script(yaml_path, dot_path)
      assert_equal 0, status
      assert_includes out, "PASS"
    end
  end

  def test_no_args_exits_1
    _out, status = run_script("", "")
    assert_equal 1, status
  end

  def test_fail_on_graph_id_mismatch
    config = {
      "required_gates" => [],
      "expand_spec_prompt" => "Read the spec.",
      "model_stylesheet" => "* { llm_model: claude-sonnet-4-6; }",
      "graph_id" => "expected_pipeline"
    }
    dot = make_dot(gates: [])
    with_files(config, dot) do |yaml_path, dot_path|
      out, status = run_script(yaml_path, dot_path)
      assert_equal 1, status
      assert_includes out, "MISMATCH graph_id"
      assert_includes out, "expected_pipeline"
    end
  end

  def test_fail_on_retry_target_mismatch
    dot_with_retry = <<~DOT
      digraph test {
        graph [
          goal="test",
          retry_target="wrong_target",
          model_stylesheet="* { llm_model: claude-sonnet-4-6; }"
        ]
        start [shape=Mdiamond]
        exit [shape=Msquare]
        expand_spec [shape=box, prompt="Read the spec."]
      }
    DOT
    config = {
      "required_gates" => [],
      "expand_spec_prompt" => "Read the spec.",
      "model_stylesheet" => "* { llm_model: claude-sonnet-4-6; }",
      "retry_target" => "implement"
    }
    with_files(config, dot_with_retry) do |yaml_path, dot_path|
      out, status = run_script(yaml_path, dot_path)
      assert_equal 1, status
      assert_includes out, "MISMATCH retry_target"
    end
  end

  def test_fail_on_missing_node_from_inventory
    config = {
      "required_gates" => [],
      "expand_spec_prompt" => "Read the spec.",
      "model_stylesheet" => "* { llm_model: claude-sonnet-4-6; }",
      "nodes" => [
        {"id" => "start", "shape" => "Mdiamond"},
        {"id" => "missing_node", "shape" => "box"}
      ]
    }
    dot = make_dot(gates: [])
    with_files(config, dot) do |yaml_path, dot_path|
      out, status = run_script(yaml_path, dot_path)
      assert_equal 1, status
      assert_includes out, 'MISSING NODE: "missing_node"'
    end
  end

  def test_fail_on_shape_mismatch
    config = {
      "required_gates" => [],
      "expand_spec_prompt" => "Read the spec.",
      "model_stylesheet" => "* { llm_model: claude-sonnet-4-6; }",
      "nodes" => [
        {"id" => "start", "shape" => "box"}
      ]
    }
    dot = make_dot(gates: [])
    with_files(config, dot) do |yaml_path, dot_path|
      out, status = run_script(yaml_path, dot_path)
      assert_equal 1, status
      assert_includes out, "SHAPE MISMATCH"
      assert_includes out, "start"
    end
  end

  def test_fail_on_extra_box_node
    dot_with_extra = <<~DOT
      digraph test {
        graph [
          goal="test",
          model_stylesheet="* { llm_model: claude-sonnet-4-6; }"
        ]
        start [shape=Mdiamond]
        exit [shape=Msquare]
        expand_spec [shape=box, prompt="Read the spec."]
        rogue_node [shape=box, prompt="I should not be here."]
      }
    DOT
    config = {
      "required_gates" => [],
      "expand_spec_prompt" => "Read the spec.",
      "model_stylesheet" => "* { llm_model: claude-sonnet-4-6; }",
      "nodes" => [
        {"id" => "start", "shape" => "Mdiamond"},
        {"id" => "exit", "shape" => "Msquare"},
        {"id" => "expand_spec", "shape" => "box"}
      ]
    }
    with_files(config, dot_with_extra) do |yaml_path, dot_path|
      out, status = run_script(yaml_path, dot_path)
      assert_equal 1, status
      assert_includes out, "EXTRA BOX NODE"
      assert_includes out, "rogue_node"
    end
  end

  def test_pass_with_all_structural_constraints
    dot_full = <<~DOT
      digraph my_pipeline {
        graph [
          goal="test",
          retry_target="implement",
          fallback_retry_target="human_gate",
          model_stylesheet="* { llm_model: claude-sonnet-4-6; }"
        ]
        start [shape=Mdiamond]
        exit [shape=Msquare]
        expand_spec [shape=box, prompt="Read the spec."]
        implement [shape=box, class="hard"]
        check_impl [shape=diamond]
        human_gate [shape=hexagon]
      }
    DOT
    config = {
      "required_gates" => [],
      "expand_spec_prompt" => "Read the spec.",
      "model_stylesheet" => "* { llm_model: claude-sonnet-4-6; }",
      "graph_id" => "my_pipeline",
      "retry_target" => "implement",
      "fallback_retry_target" => "human_gate",
      "nodes" => [
        {"id" => "start", "shape" => "Mdiamond"},
        {"id" => "exit", "shape" => "Msquare"},
        {"id" => "expand_spec", "shape" => "box"},
        {"id" => "implement", "shape" => "box"},
        {"id" => "check_impl", "shape" => "diamond"},
        {"id" => "human_gate", "shape" => "hexagon"}
      ]
    }
    with_files(config, dot_full) do |yaml_path, dot_path|
      out, status = run_script(yaml_path, dot_path)
      assert_equal 0, status
      assert_includes out, "PASS"
      assert_includes out, "graph_id: my_pipeline"
      assert_includes out, "retry_target: implement"
      assert_includes out, "6 nodes verified"
    end
  end

  def test_pass_with_edges
    dot = <<~DOT
      digraph test {
        graph [goal="test", model_stylesheet="* { llm_model: claude-sonnet-4-6; }"]
        start [shape=Mdiamond]
        expand_spec [shape=box, prompt="Read the spec."]
        work [shape=box, prompt="Do stuff."]
        check [shape=diamond]
        exit [shape=Msquare]
        start -> expand_spec
        expand_spec -> work
        work -> check
        check -> exit [condition="outcome = success"]
        check -> work [condition="outcome = fail", loop_restart=true]
        check -> exit
      }
    DOT
    config = {
      "required_gates" => [],
      "expand_spec_prompt" => "Read the spec.",
      "model_stylesheet" => "* { llm_model: claude-sonnet-4-6; }",
      "edges" => [
        {"from" => "start", "to" => "expand_spec"},
        {"from" => "expand_spec", "to" => "work"},
        {"from" => "work", "to" => "check"},
        {"from" => "check", "to" => "exit", "condition" => "outcome = success"},
        {"from" => "check", "to" => "work", "condition" => "outcome = fail", "loop_restart" => true},
        {"from" => "check", "to" => "exit"}
      ]
    }
    with_files(config, dot) do |yaml_path, dot_path|
      out, status = run_script(yaml_path, dot_path)
      assert_equal 0, status
      assert_includes out, "PASS"
      assert_includes out, "6 edges verified"
    end
  end

  def test_fail_on_missing_edge
    dot = <<~DOT
      digraph test {
        graph [goal="test", model_stylesheet="* { llm_model: claude-sonnet-4-6; }"]
        start [shape=Mdiamond]
        work [shape=box, prompt="Do stuff."]
        exit [shape=Msquare]
        start -> work
      }
    DOT
    config = {
      "required_gates" => [],
      "expand_spec_prompt" => "Read the spec.",
      "model_stylesheet" => "* { llm_model: claude-sonnet-4-6; }",
      "edges" => [
        {"from" => "start", "to" => "work"},
        {"from" => "work", "to" => "exit"}
      ]
    }
    with_files(config, dot) do |yaml_path, dot_path|
      out, status = run_script(yaml_path, dot_path)
      assert_equal 1, status
      assert_includes out, "MISSING EDGE"
      assert_includes out, "work -> exit"
    end
  end

  def test_fail_on_missing_conditional_edge
    dot = <<~DOT
      digraph test {
        graph [goal="test", model_stylesheet="* { llm_model: claude-sonnet-4-6; }"]
        check [shape=diamond]
        work [shape=box, prompt="Do stuff."]
        exit [shape=Msquare]
        check -> exit [condition="outcome = success"]
      }
    DOT
    config = {
      "required_gates" => [],
      "expand_spec_prompt" => "Read the spec.",
      "model_stylesheet" => "* { llm_model: claude-sonnet-4-6; }",
      "edges" => [
        {"from" => "check", "to" => "exit", "condition" => "outcome = success"},
        {"from" => "check", "to" => "work", "condition" => "outcome = fail"}
      ]
    }
    with_files(config, dot) do |yaml_path, dot_path|
      out, status = run_script(yaml_path, dot_path)
      assert_equal 1, status
      assert_includes out, "MISSING EDGE"
      assert_includes out, "check -> work"
    end
  end
end

