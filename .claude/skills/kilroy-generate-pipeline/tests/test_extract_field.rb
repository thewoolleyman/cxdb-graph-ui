#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "tempfile"
require "yaml"
require "json"

class TestExtractField < Minitest::Test
  SCRIPT = File.join(__dir__, "../script", "extract_field.rb")

  def with_yaml_file(data)
    f = Tempfile.new(["test", ".yaml"])
    f.write(YAML.dump(data))
    f.close
    yield f.path
  ensure
    f.unlink
  end

  def run_script(*args)
    out = `ruby #{SCRIPT} #{args.join(" ")} 2>&1`
    [out, $?.exitstatus]
  end

  def test_extract_string_field
    with_yaml_file("target" => "lab-bench", "repo_path" => "../lab-bench-poc") do |path|
      out, status = run_script(path, "target")
      assert_equal 0, status
      assert_equal "lab-bench", out
    end
  end

  def test_extract_multiline_string
    with_yaml_file("goal" => "Line one.\nLine two.\n") do |path|
      out, status = run_script(path, "goal")
      assert_equal 0, status
      assert_equal "Line one.\nLine two.\n", out
    end
  end

  def test_extract_array_field
    gates = [{"id" => "verify_build", "tool_command" => "cargo build"}]
    with_yaml_file("required_gates" => gates) do |path|
      out, status = run_script(path, "required_gates")
      assert_equal 0, status
      parsed = JSON.parse(out)
      assert_equal "verify_build", parsed[0]["id"]
    end
  end

  def test_missing_field_exits_1
    with_yaml_file("target" => "lab-bench") do |path|
      _out, status = run_script(path, "nonexistent")
      assert_equal 1, status
    end
  end

  def test_no_args_exits_1
    _out, status = run_script
    assert_equal 1, status
  end
end
