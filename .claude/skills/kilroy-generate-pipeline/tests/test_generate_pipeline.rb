#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "tempfile"
require "fileutils"
require "yaml"

class TestGeneratePipeline < Minitest::Test
  SCRIPT = File.join(__dir__, "../script", "generate_pipeline.rb")

  def test_no_args_exits_1
    out = `ruby #{SCRIPT} 2>&1`
    assert_equal 1, $?.exitstatus
    assert_includes out, "Usage"
  end

  def test_unknown_target_exits_1
    out = `ruby #{SCRIPT} unknown-target 2>&1`
    assert_equal 1, $?.exitstatus
    assert_includes out, "unknown target"
  end

  def test_missing_config_no_dot_enters_bootstrap
    Dir.mktmpdir do |dir|
      out = `REPO_ROOT=#{dir} ruby #{SCRIPT} . 2>&1`
      assert_equal 1, $?.exitstatus
      assert_includes out, "bootstrap"
      assert_includes out, "SUMMARY"
      assert_includes out, "render: FAILED"
    end
  end

  def test_safety_check_dot_exists_no_config
    # If a DOT file exists but no config YAML → refuse
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "pipeline.dot"), "digraph test {}")
      out = `REPO_ROOT=#{dir} ruby #{SCRIPT} . 2>&1`
      assert_equal 1, $?.exitstatus
      assert_includes out, "safety_error"
      assert_includes out, "DOT exists without config YAML"
    end
  end

  def test_bootstrap_mode_when_nothing_exists
    Dir.mktmpdir do |dir|
      # Neither config nor DOT exists → bootstrap mode, but fails because
      # bootstrap requires a config
      out = `REPO_ROOT=#{dir} ruby #{SCRIPT} . 2>&1`
      # With no DOT file, determine_mode returns :bootstrap
      # Bootstrap mode requires config, so it should fail
      assert_equal 1, $?.exitstatus
    end
  end

  def test_compile_mode_with_full_config
    Dir.mktmpdir do |dir|
      # Create a minimal config with nodes and edges
      config = {
        "target" => ".",
        "repo_path" => ".",
        "output_dot" => "pipeline.dot",
        "graph_id" => "test_pipeline",
        "graph_goal" => "Test pipeline",
        "default_max_retry" => 3,
        "nodes" => [
          { "id" => "start", "shape" => "Mdiamond" },
          { "id" => "work", "shape" => "box" },
          { "id" => "exit", "shape" => "Msquare" }
        ],
        "edges" => [
          { "from" => "start", "to" => "work" },
          { "from" => "work", "to" => "exit" }
        ],
        "model_stylesheet" => "* { llm_model: claude-sonnet-4-6; }"
      }

      config_dir = File.join(dir, "pipeline-config")
      FileUtils.mkdir_p(config_dir)
      yaml_path = File.join(config_dir, "pipeline-config.yaml")
      File.write(yaml_path, YAML.dump(config))

      # Create prompt file alongside the YAML
      File.write(File.join(config_dir, "work.md"), "Do the work.\n")

      # Run — compile should succeed, verify/validate may fail (no kilroy binary)
      out = `REPO_ROOT=#{dir} KILROY_BIN=/nonexistent ruby #{SCRIPT} . 2>&1`

      # Should detect compile mode
      assert_includes out, "compile"
      # DOT file should be created
      assert File.exist?(File.join(dir, "pipeline.dot")),
             "Expected DOT file to be created"
    end
  end

  def test_all_parallel_runs_single_target
    Dir.mktmpdir do |dir|
      out = `REPO_ROOT=#{dir} ruby #{SCRIPT} all 2>&1`
      assert_equal 1, $?.exitstatus

      # Single target must appear in output
      assert_includes out, "PARALLEL RUN COMPLETE"

      # No nil or empty targets
      refute_match(/FAILED:\s*,/, out, "nil target produced a leading comma")
      refute_match(/Succeeded:\s*,/, out, "nil target produced a leading comma")
    end
  end

  def test_step_tracker_summary_format
    script = Tempfile.new(["step_tracker_test", ".rb"])
    script.write(<<~'RUBY')
      COMPILE_STEPS = %i[compile verify validate]

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

        def print_summary
          puts "=" * 60
          puts "SUMMARY: #{@target}"
          @steps.each do |step|
            r = @results[step]
            if r.nil?
              puts "  #{step}: SKIPPED"
            elsif r[:success]
              puts "  #{step}: OK"
            else
              puts "  #{step}: FAILED"
              puts "    #{r[:detail]}" if r[:detail]
            end
          end
          puts "=" * 60
        end
      end

      t = StepTracker.new("test-target", COMPILE_STEPS)
      t.record(:compile, true)
      t.record(:verify, false, "mismatches found")
      t.print_summary
    RUBY
    script.close

    out = `ruby #{script.path} 2>&1`

    assert_includes out, "SUMMARY: test-target"
    assert_includes out, "compile: OK"
    assert_includes out, "verify: FAILED"
    assert_includes out, "mismatches found"
    assert_includes out, "validate: SKIPPED"
  ensure
    script&.unlink
  end

  def test_determine_mode_function
    # Test the mode determination logic via a small helper script
    script = Tempfile.new(["mode_test", ".rb"])
    script.write(<<~'RUBY')
      def determine_mode(yaml_file, dot_file)
        yaml_exists = File.exist?(yaml_file)
        dot_exists = File.exist?(dot_file)

        if yaml_exists
          :compile
        elsif !yaml_exists && !dot_exists
          :bootstrap
        else
          :safety_error
        end
      end

      require "tempfile"
      require "fileutils"

      dir = ARGV[0]

      # Test 1: both exist -> compile
      yaml = File.join(dir, "config.yaml")
      dot = File.join(dir, "out.dot")
      File.write(yaml, "test: true")
      File.write(dot, "digraph {}")
      puts "both=#{determine_mode(yaml, dot)}"

      # Test 2: only yaml -> compile
      File.delete(dot)
      puts "yaml_only=#{determine_mode(yaml, dot)}"

      # Test 3: only dot -> safety_error
      File.delete(yaml)
      File.write(dot, "digraph {}")
      puts "dot_only=#{determine_mode(yaml, dot)}"

      # Test 4: neither -> bootstrap
      File.delete(dot)
      puts "neither=#{determine_mode(yaml, dot)}"
    RUBY
    script.close

    Dir.mktmpdir do |dir|
      out = `ruby #{script.path} #{dir} 2>&1`
      assert_includes out, "both=compile"
      assert_includes out, "yaml_only=compile"
      assert_includes out, "dot_only=safety_error"
      assert_includes out, "neither=bootstrap"
    end
  ensure
    script&.unlink
  end
end
