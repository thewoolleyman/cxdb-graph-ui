#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "tempfile"
require "fileutils"
require "yaml"

class TestExtractPrompts < Minitest::Test
  SCRIPT = File.join(__dir__, "../script", "extract_prompts.rb")

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

  def write_dot(content)
    path = File.join(@tmpdir, "pipeline-test.dot")
    File.write(path, content)
    path
  end

  def test_no_args_exits_1
    out = `ruby #{SCRIPT} 2>&1`
    assert_equal 1, $?.exitstatus
    assert_includes out, "Usage"
  end

  def test_extracts_box_node_prompt
    yaml = write_yaml(<<~YAML)
      target: mytest
      repo_path: .
      output_dot: pipeline-test.dot
    YAML

    dot = write_dot(<<~'DOT')
      digraph test_pipeline {
        implement [shape=box, class="hard", prompt="## Task\n\nDo the thing.\n\n## Status\n\nWrite to $KILROY_STAGE_STATUS_PATH."]
      }
    DOT

    out = `ruby #{SCRIPT} #{yaml} #{dot} 2>&1`
    assert_equal 0, $?.exitstatus
    assert_includes out, "Extracted prompt"

    prompt_file = File.join(@tmpdir, "prompts", "implement.md")
    assert File.exist?(prompt_file), "Expected #{prompt_file} to exist"

    content = File.read(prompt_file)
    assert_includes content, "## Task"
    assert_includes content, "Do the thing."
    assert_includes content, "$KILROY_STAGE_STATUS_PATH"
  end

  def test_extracts_hexagon_question
    yaml = write_yaml(<<~YAML)
      target: mytest
      repo_path: .
      output_dot: pipeline-test.dot
    YAML

    dot = write_dot(<<~'DOT')
      digraph test_pipeline {
        human_gate [shape=hexagon, question="Pipeline has exhausted retries.\n\nCheck /kilroy:status for details.", choices="[R] Retry;[A] Abort"]
      }
    DOT

    out = `ruby #{SCRIPT} #{yaml} #{dot} 2>&1`
    assert_equal 0, $?.exitstatus
    assert_includes out, "Extracted question"

    question_file = File.join(@tmpdir, "prompts", "human_gate.md")
    assert File.exist?(question_file), "Expected #{question_file} to exist"

    content = File.read(question_file)
    assert_includes content, "Pipeline has exhausted retries."
    assert_includes content, "/kilroy:status"
  end

  def test_skips_expand_spec
    yaml = write_yaml(<<~YAML)
      target: mytest
      repo_path: .
      output_dot: pipeline-test.dot
    YAML

    dot = write_dot(<<~'DOT')
      digraph test_pipeline {
        expand_spec [shape=box, prompt="Read the spec files."]
        implement [shape=box, prompt="Do the thing."]
      }
    DOT

    `ruby #{SCRIPT} #{yaml} #{dot} 2>&1`

    expand_file = File.join(@tmpdir, "prompts", "expand_spec.md")
    refute File.exist?(expand_file), "expand_spec.md should NOT be created"

    implement_file = File.join(@tmpdir, "prompts", "implement.md")
    assert File.exist?(implement_file), "implement.md should be created"
  end

  def test_handles_multiline_prompt_with_escaped_quotes
    yaml = write_yaml(<<~YAML)
      target: mytest
      repo_path: .
      output_dot: pipeline-test.dot
    YAML

    dot = write_dot(<<~'DOT')
      digraph test_pipeline {
        review [shape=box, class="verify", prompt="Check that:\n- Field uses `package gitlab.bench.v1;`\n- Uses `syntax = \"proto3\";`\n\nWrite status."]
      }
    DOT

    `ruby #{SCRIPT} #{yaml} #{dot} 2>&1`

    content = File.read(File.join(@tmpdir, "prompts", "review.md"))
    assert_includes content, 'syntax = "proto3";'
    assert_includes content, "package gitlab.bench.v1;"
  end

  def test_extracts_multiple_nodes
    yaml = write_yaml(<<~YAML)
      target: mytest
      repo_path: .
      output_dot: pipeline-test.dot
    YAML

    dot = write_dot(<<~'DOT')
      digraph test_pipeline {
        start [shape=Mdiamond]
        implement [shape=box, prompt="Implement stuff."]
        check_implement [shape=diamond]
        review [shape=box, prompt="Review stuff."]
        postmortem [shape=box, prompt="Analyze failure."]
        human_gate [shape=hexagon, question="Need help?", choices="[R] Retry;[A] Abort"]
        exit [shape=Msquare]
      }
    DOT

    out = `ruby #{SCRIPT} #{yaml} #{dot} 2>&1`
    assert_equal 0, $?.exitstatus
    assert_includes out, "extracted 4 prompt(s)"

    prompts_dir = File.join(@tmpdir, "prompts")
    assert File.exist?(File.join(prompts_dir, "implement.md"))
    assert File.exist?(File.join(prompts_dir, "review.md"))
    assert File.exist?(File.join(prompts_dir, "postmortem.md"))
    assert File.exist?(File.join(prompts_dir, "human_gate.md"))
    # Mdiamond, Msquare, diamond should NOT produce files
    refute File.exist?(File.join(prompts_dir, "start.md"))
    refute File.exist?(File.join(prompts_dir, "exit.md"))
    refute File.exist?(File.join(prompts_dir, "check_implement.md"))
  end

  def test_prompt_files_end_with_newline
    yaml = write_yaml(<<~YAML)
      target: mytest
      repo_path: .
      output_dot: pipeline-test.dot
    YAML

    dot = write_dot(<<~'DOT')
      digraph test_pipeline {
        implement [shape=box, prompt="Do the thing."]
      }
    DOT

    `ruby #{SCRIPT} #{yaml} #{dot} 2>&1`
    content = File.read(File.join(@tmpdir, "prompts", "implement.md"))
    assert content.end_with?("\n"), "Prompt file should end with newline"
  end

  def test_missing_target_field_exits_1
    yaml = write_yaml(<<~YAML)
      repo_path: .
      output_dot: pipeline-test.dot
    YAML

    dot = write_dot("digraph test { }")
    out = `ruby #{SCRIPT} #{yaml} #{dot} 2>&1`
    assert_equal 1, $?.exitstatus
    assert_includes out, "missing 'target'"
  end
end
