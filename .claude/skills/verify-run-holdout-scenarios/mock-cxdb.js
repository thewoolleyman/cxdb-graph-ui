/**
 * mock-cxdb.js — Browser-injectable mock for CXDB API endpoints.
 *
 * Inject via playwright_evaluate after navigation. Overrides window.fetch
 * to intercept all /api/cxdb/* requests and return scenario-specific data.
 *
 * Usage:
 *   await page.evaluate(fs.readFileSync('mock-cxdb.js', 'utf8'));
 *   await page.evaluate("window.__mockCxdb.setScenario('pipeline_running')");
 *
 * Available scenarios:
 *   no_pipeline           — CXDB running, no contexts match; all nodes gray
 *   pipeline_running      — implement complete (green), fix_fmt running (blue)
 *   pipeline_complete     — all nodes complete (green)
 *   error_loop            — implement has 3 consecutive ToolResult errors → red
 *   pipeline_stalled      — implement was running, now is_live=false → orange
 *   parallel_branches     — two contexts for same pipeline/run, parallel nodes
 *   stage_failed_retry    — StageFailed(will_retry=true) → implement stays blue
 *   stage_finished_fail   — StageFinished(status=fail) → implement red
 *   run_failed            — RunFailed on implement → red
 *   second_run            — older run A (complete) + newer run B (partial); B wins
 *   cxdb_unreachable      — all /api/cxdb/* return 502
 *   cxdb_partial          — CXDB-0 ok (pipeline_running), CXDB-1 returns 502
 *   cql_not_supported     — /search returns 404, /contexts fallback used
 *   human_gate_interview  — InterviewStarted + InterviewCompleted turns
 *   interview_timeout     — InterviewTimeout turn
 *   stage_started_types   — multiple StageStarted turns with handler_type variants
 *   stage_finished_next   — StageFinished with suggested_next_ids
 *   prompt_long           — Prompt turn with 50,000-character text
 *   conditional_custom    — conditional node with custom routing value "process"
 *   all_shapes_complete   — all node shapes complete (for all-shapes fixture)
 */
(function () {
  'use strict';

  // ─── Minimal msgpack encoder ────────────────────────────────────────────────
  // Supports: fixmap, fixarray, fixstr, str8, str16, nil, bool, uint8, uint32
  function packMsgpack(obj) {
    const bytes = [];
    const enc = new TextEncoder();

    function packStr(s) {
      const bs = enc.encode(s);
      if (bs.length <= 31) {
        bytes.push(0xa0 | bs.length);
      } else if (bs.length <= 255) {
        bytes.push(0xd9, bs.length);
      } else {
        bytes.push(0xda, (bs.length >> 8) & 0xff, bs.length & 0xff);
      }
      bytes.push(...bs);
    }

    function packVal(v) {
      if (v === null || v === undefined) {
        bytes.push(0xc0);
      } else if (typeof v === 'boolean') {
        bytes.push(v ? 0xc3 : 0xc2);
      } else if (typeof v === 'number') {
        if (Number.isInteger(v) && v >= 0 && v <= 127) {
          bytes.push(v);
        } else if (Number.isInteger(v) && v >= 0 && v <= 255) {
          bytes.push(0xcc, v);
        } else if (Number.isInteger(v) && v >= 0 && v <= 0xffffffff) {
          bytes.push(0xce, (v >>> 24) & 0xff, (v >>> 16) & 0xff, (v >>> 8) & 0xff, v & 0xff);
        } else {
          // Fallback: encode as fixint with truncation (shouldn't happen in our data)
          bytes.push(v & 0x7f);
        }
      } else if (typeof v === 'string') {
        packStr(v);
      } else if (Array.isArray(v)) {
        if (v.length <= 15) {
          bytes.push(0x90 | v.length);
        } else {
          bytes.push(0xdc, (v.length >> 8) & 0xff, v.length & 0xff);
        }
        v.forEach(packVal);
      } else if (typeof v === 'object') {
        const keys = Object.keys(v);
        if (keys.length <= 15) {
          bytes.push(0x80 | keys.length);
        } else {
          bytes.push(0xde, (keys.length >> 8) & 0xff, keys.length & 0xff);
        }
        keys.forEach(k => { packStr(k); packVal(v[k]); });
      }
    }

    packVal(obj);
    return btoa(String.fromCharCode(...bytes));
  }

  // ─── Turn ID counter ─────────────────────────────────────────────────────────
  let _turnId = 0;
  function nextId() { return String(++_turnId); }
  function resetIds() { _turnId = 0; }

  // ─── Turn constructors ───────────────────────────────────────────────────────
  const T = {
    runStarted: (graphName, runId) => ({
      turn_id: nextId(), declared_type: 'com.kilroy.attractor.RunStarted',
      data: { graph_name: graphName, run_id: runId }
    }),
    stageStarted: (nodeId, handlerType = 'codergen') => ({
      turn_id: nextId(), declared_type: 'com.kilroy.attractor.StageStarted',
      data: { node_id: nodeId, handler_type: handlerType }
    }),
    stageFinished: (nodeId, status = 'pass', preferredLabel = 'pass', suggestedNextIds = []) => ({
      turn_id: nextId(), declared_type: 'com.kilroy.attractor.StageFinished',
      data: { node_id: nodeId, status, preferred_label: preferredLabel, suggested_next_ids: suggestedNextIds }
    }),
    stageFailed: (nodeId, willRetry = false) => ({
      turn_id: nextId(), declared_type: 'com.kilroy.attractor.StageFailed',
      data: { node_id: nodeId, will_retry: willRetry }
    }),
    stageRetrying: (nodeId) => ({
      turn_id: nextId(), declared_type: 'com.kilroy.attractor.StageRetrying',
      data: { node_id: nodeId }
    }),
    runFailed: (nodeId, reason) => ({
      turn_id: nextId(), declared_type: 'com.kilroy.attractor.RunFailed',
      data: { node_id: nodeId, reason }
    }),
    toolCall: (toolName, content) => ({
      turn_id: nextId(), declared_type: 'ToolCall',
      data: { tool_name: toolName, content }
    }),
    toolResult: (toolName, content, isError = false) => ({
      turn_id: nextId(), declared_type: 'ToolResult',
      data: { tool_name: toolName, content, is_error: isError }
    }),
    prompt: (text) => ({
      turn_id: nextId(), declared_type: 'Prompt',
      data: { text }
    }),
    assistantMessage: (content) => ({
      turn_id: nextId(), declared_type: 'AssistantMessage',
      data: { content }
    }),
    interviewStarted: (nodeId, questionText, questionType = 'SingleSelect') => ({
      turn_id: nextId(), declared_type: 'com.kilroy.attractor.InterviewStarted',
      data: { node_id: nodeId, question_text: questionText, question_type: questionType }
    }),
    interviewCompleted: (nodeId, answerValue, durationMs) => ({
      turn_id: nextId(), declared_type: 'com.kilroy.attractor.InterviewCompleted',
      data: { node_id: nodeId, answer_value: answerValue, duration_ms: durationMs }
    }),
    interviewTimeout: (nodeId, questionText, durationMs) => ({
      turn_id: nextId(), declared_type: 'com.kilroy.attractor.InterviewTimeout',
      data: { node_id: nodeId, question_text: questionText, duration_ms: durationMs }
    }),
  };

  // ─── Context builder ─────────────────────────────────────────────────────────
  function ctx(contextId, runId, isLive = true) {
    return { context_id: String(contextId), client_tag: `kilroy/${runId}`, is_live: isLive };
  }

  // ─── ULID-style fake run IDs ─────────────────────────────────────────────────
  const RUN_A = '01JZAAAAAAAAAAAAAAAAAAAAAA'; // older run
  const RUN_B = '01JZBBBBBBBBBBBBBBBBBBBBBB'; // newer run (lexicographically later)
  const RUN_1 = '01JZCCCCCCCCCCCCCCCCCCCCCC'; // single run for most scenarios

  // ─── Scenario definitions ────────────────────────────────────────────────────
  // Each scenario provides: contexts (per cxdb index) and turns (per context_id).
  // contexts[i] = array of context objects for CXDB instance i.
  // turns[contextId] = array of turns, newest first (as CXDB returns with order=desc).

  function buildScenarios() {
    resetIds();

    return {

      // ── no_pipeline ──────────────────────────────────────────────────────────
      no_pipeline: {
        contexts: { 0: [] },
        turns: {},
      },

      // ── pipeline_running ─────────────────────────────────────────────────────
      // implement: complete (green); fix_fmt: running (blue)
      pipeline_running: {
        contexts: { 0: [ctx('42', RUN_1)] },
        turns: {
          '42': [
            // Returned newest-first by CXDB (order=desc)
            T.toolCall('shell', 'grep -r TODO src/'),
            T.stageStarted('fix_fmt', 'codergen'),
            T.stageFinished('implement', 'pass', 'pass', ['fix_fmt']),
            T.stageStarted('implement', 'codergen'),
            T.runStarted('simple_pipeline', RUN_1),
          ],
        },
      },

      // ── pipeline_complete ────────────────────────────────────────────────────
      pipeline_complete: {
        contexts: { 0: [ctx('42', RUN_1, false)] },
        turns: {
          '42': [
            T.stageFinished('review_gate', 'pass', 'approve', ['done']),
            T.interviewCompleted('review_gate', 'approve', 3000),
            T.interviewStarted('review_gate', 'Approve the implementation?'),
            T.stageStarted('review_gate', 'human_gate'),
            T.stageFinished('check_fmt', 'pass', 'pass', ['review_gate']),
            T.stageStarted('check_fmt', 'tool'),
            T.stageFinished('fix_fmt', 'pass', 'pass', ['check_fmt']),
            T.stageStarted('fix_fmt', 'codergen'),
            T.stageFinished('implement', 'pass', 'pass', ['fix_fmt']),
            T.stageStarted('implement', 'codergen'),
            T.runStarted('simple_pipeline', RUN_1),
          ],
        },
      },

      // ── error_loop ───────────────────────────────────────────────────────────
      // fix_fmt: 3 consecutive ToolResult errors → red
      error_loop: {
        contexts: { 0: [ctx('42', RUN_1)] },
        turns: {
          '42': [
            T.toolResult('shell', 'Error: command not found', true),
            T.toolCall('shell', 'nonexistent-tool'),
            T.toolResult('shell', 'Error: permission denied', true),
            T.toolCall('shell', 'sudo rm -rf /'),
            T.toolResult('shell', 'Error: file not found', true),
            T.toolCall('shell', 'cat missing.txt'),
            T.stageStarted('fix_fmt', 'codergen'),
            T.stageFinished('implement', 'pass', 'pass', ['fix_fmt']),
            T.stageStarted('implement', 'codergen'),
            T.runStarted('simple_pipeline', RUN_1),
          ],
        },
      },

      // ── pipeline_stalled ─────────────────────────────────────────────────────
      // fix_fmt was running; all contexts now is_live=false → orange
      pipeline_stalled: {
        contexts: { 0: [ctx('42', RUN_1, false)] }, // is_live: false
        turns: {
          '42': [
            T.toolCall('shell', 'make build'),
            T.stageStarted('fix_fmt', 'codergen'),
            T.stageFinished('implement', 'pass', 'pass', ['fix_fmt']),
            T.stageStarted('implement', 'codergen'),
            T.runStarted('simple_pipeline', RUN_1),
          ],
        },
      },

      // ── parallel_branches ────────────────────────────────────────────────────
      // Two contexts, same run_id; both have different nodes running
      parallel_branches: {
        contexts: { 0: [ctx('42', RUN_1), ctx('43', RUN_1)] },
        turns: {
          '42': [
            T.stageStarted('fix_fmt', 'codergen'),
            T.stageFinished('implement', 'pass', 'pass', ['fix_fmt']),
            T.stageStarted('implement', 'codergen'),
            T.runStarted('simple_pipeline', RUN_1),
          ],
          '43': [
            T.stageStarted('check_fmt', 'tool'),
            T.runStarted('simple_pipeline', RUN_1),
          ],
        },
      },

      // ── stage_failed_retry ───────────────────────────────────────────────────
      // StageFailed(will_retry=true) + StageRetrying + StageStarted → blue
      stage_failed_retry: {
        contexts: { 0: [ctx('42', RUN_1)] },
        turns: {
          '42': [
            T.stageStarted('fix_fmt', 'codergen'),
            T.stageRetrying('fix_fmt'),
            T.stageFailed('fix_fmt', true),
            T.stageStarted('fix_fmt', 'codergen'),
            T.runStarted('simple_pipeline', RUN_1),
          ],
        },
      },

      // ── stage_finished_fail ──────────────────────────────────────────────────
      // StageFinished(status=fail) → red
      stage_finished_fail: {
        contexts: { 0: [ctx('42', RUN_1)] },
        turns: {
          '42': [
            T.stageFinished('fix_fmt', 'fail', 'fail', []),
            T.stageStarted('fix_fmt', 'codergen'),
            T.stageFinished('implement', 'pass', 'pass', ['fix_fmt']),
            T.stageStarted('implement', 'codergen'),
            T.runStarted('simple_pipeline', RUN_1),
          ],
        },
      },

      // ── run_failed ───────────────────────────────────────────────────────────
      // RunFailed on implement → red
      run_failed: {
        contexts: { 0: [ctx('42', RUN_1)] },
        turns: {
          '42': [
            T.runFailed('fix_fmt', 'agent crashed unexpectedly'),
            T.stageStarted('fix_fmt', 'codergen'),
            T.runStarted('simple_pipeline', RUN_1),
          ],
        },
      },

      // ── second_run ───────────────────────────────────────────────────────────
      // Older run A (complete, context 10) + newer run B (partial, context 11)
      // Active run should be B (newer ULID); A's completed nodes should not show
      second_run: {
        contexts: {
          0: [
            ctx('10', RUN_A, false), // older completed run
            ctx('11', RUN_B),        // newer active run
          ],
        },
        turns: {
          '10': [
            // Run A: full pipeline complete
            T.stageFinished('review_gate', 'pass', 'approve', []),
            T.stageFinished('check_fmt', 'pass', 'pass', ['review_gate']),
            T.stageFinished('fix_fmt', 'pass', 'pass', ['check_fmt']),
            T.stageFinished('implement', 'pass', 'pass', ['fix_fmt']),
            T.runStarted('simple_pipeline', RUN_A),
          ],
          '11': [
            // Run B: only implement done, fix_fmt running
            T.stageStarted('fix_fmt', 'codergen'),
            T.stageFinished('implement', 'pass', 'pass', ['fix_fmt']),
            T.stageStarted('implement', 'codergen'),
            T.runStarted('simple_pipeline', RUN_B),
          ],
        },
      },

      // ── cxdb_unreachable ─────────────────────────────────────────────────────
      // All /api/cxdb/* requests return 502
      cxdb_unreachable: {
        contexts: {},
        turns: {},
        _mode: 'unreachable',
      },

      // ── cxdb_partial ─────────────────────────────────────────────────────────
      // CXDB-0 has pipeline_running data; CXDB-1 returns 502
      cxdb_partial: {
        contexts: {
          0: [ctx('42', RUN_1)],
          1: null, // null signals 502
        },
        turns: {
          '42': [
            T.toolCall('shell', 'make build'),
            T.stageStarted('fix_fmt', 'codergen'),
            T.stageFinished('implement', 'pass', 'pass', ['fix_fmt']),
            T.runStarted('simple_pipeline', RUN_1),
          ],
        },
      },

      // ── cql_not_supported ────────────────────────────────────────────────────
      // /contexts/search returns 404; UI should fall back to /contexts list
      cql_not_supported: {
        contexts: { 0: [ctx('42', RUN_1)] },
        turns: {
          '42': [
            T.stageStarted('fix_fmt', 'codergen'),
            T.stageFinished('implement', 'pass', 'pass', ['fix_fmt']),
            T.runStarted('simple_pipeline', RUN_1),
          ],
        },
        _mode: 'cql_404',
      },

      // ── human_gate_interview ─────────────────────────────────────────────────
      // InterviewStarted + InterviewCompleted for review_gate node
      human_gate_interview: {
        contexts: { 0: [ctx('42', RUN_1, false)] },
        turns: {
          '42': [
            T.stageFinished('review_gate', 'pass', 'approve', ['done']),
            T.interviewCompleted('review_gate', 'YES', 45000),
            T.interviewStarted('review_gate', 'Approve the implementation?', 'SingleSelect'),
            T.stageStarted('review_gate', 'human_gate'),
            T.stageFinished('fix_fmt', 'pass', 'pass', ['review_gate']),
            T.runStarted('simple_pipeline', RUN_1),
          ],
        },
      },

      // ── interview_timeout ────────────────────────────────────────────────────
      interview_timeout: {
        contexts: { 0: [ctx('42', RUN_1)] },
        turns: {
          '42': [
            T.interviewTimeout('review_gate', 'Confirm deployment?', 300000),
            T.interviewStarted('review_gate', 'Confirm deployment?', 'SingleSelect'),
            T.stageStarted('review_gate', 'human_gate'),
            T.runStarted('simple_pipeline', RUN_1),
          ],
        },
      },

      // ── stage_started_types ──────────────────────────────────────────────────
      // Three different StageStarted handler_type values
      stage_started_types: {
        contexts: { 0: [ctx('42', RUN_1)] },
        turns: {
          '42': [
            T.stageStarted('check_fmt', 'tool'),
            T.stageStarted('review_gate', 'human_gate'),
            T.stageStarted('fix_fmt', 'codergen'),
            T.runStarted('simple_pipeline', RUN_1),
          ],
        },
      },

      // ── stage_finished_next ──────────────────────────────────────────────────
      // StageFinished with non-empty suggested_next_ids
      stage_finished_next: {
        contexts: { 0: [ctx('42', RUN_1)] },
        turns: {
          '42': [
            T.stageStarted('fix_fmt', 'codergen'),
            T.stageFinished('implement', 'pass', 'pass', ['fix_fmt', 'check_fmt']),
            T.runStarted('simple_pipeline', RUN_1),
          ],
        },
      },

      // ── prompt_long ──────────────────────────────────────────────────────────
      // Prompt turn with 50,000 characters to test Show More cap at 8,000
      prompt_long: {
        contexts: { 0: [ctx('42', RUN_1)] },
        turns: {
          '42': [
            T.prompt('A'.repeat(50000)),
            T.stageStarted('fix_fmt', 'codergen'),
            T.runStarted('simple_pipeline', RUN_1),
          ],
        },
      },

      // ── conditional_custom ───────────────────────────────────────────────────
      // Conditional node with custom routing value (not "pass"/"fail") → green
      conditional_custom: {
        contexts: { 0: [ctx('42', RUN_1)] },
        turns: {
          '42': [
            T.stageFinished('check_quality', 'process', 'process', ['fix_fmt']),
            T.stageStarted('check_quality', 'tool'),
            T.runStarted('all_shapes', RUN_1),
          ],
        },
      },

      // ── all_shapes_complete ──────────────────────────────────────────────────
      // All nodes in all-shapes.dot marked complete
      all_shapes_complete: {
        contexts: { 0: [ctx('99', RUN_1, false)] },
        turns: {
          '99': [
            T.stageFinished('node_exit_doublecircle', 'pass', 'pass', []),
            T.stageStarted('node_exit_doublecircle', 'codergen'),
            T.stageFinished('node_stack_loop', 'pass', 'pass', ['node_exit_doublecircle']),
            T.stageStarted('node_stack_loop', 'codergen'),
            T.stageFinished('node_fan_in', 'pass', 'pass', ['node_stack_loop']),
            T.stageStarted('node_fan_in', 'codergen'),
            T.stageFinished('node_parallel', 'pass', 'pass', ['node_fan_in']),
            T.stageStarted('node_parallel', 'codergen'),
            T.stageFinished('node_human_gate', 'pass', 'approve', ['node_parallel']),
            T.stageStarted('node_human_gate', 'human_gate'),
            T.stageFinished('node_tool_gate', 'pass', 'pass', ['node_human_gate']),
            T.stageStarted('node_tool_gate', 'tool'),
            T.stageFinished('node_conditional', 'pass', 'pass', ['node_tool_gate']),
            T.stageStarted('node_conditional', 'codergen'),
            T.stageFinished('node_llm_task', 'pass', 'pass', ['node_conditional']),
            T.stageStarted('node_llm_task', 'codergen'),
            T.stageFinished('node_exit_square', 'pass', 'pass', []),
            T.stageStarted('node_exit_square', 'codergen'),
            T.runStarted('all_shapes', RUN_1),
          ],
        },
      },

    };
  }

  // ─── Mock fetch implementation ───────────────────────────────────────────────
  const origFetch = window.fetch.bind(window);
  let _scenarios = buildScenarios();

  window.__mockCxdb = {
    scenario: 'no_pipeline',

    setScenario(name) {
      if (!_scenarios[name]) {
        console.warn(`[mock-cxdb] Unknown scenario: ${name}`);
      }
      this.scenario = name;
      // Rebuild turn IDs so they're consistent within each scenario
      _scenarios = buildScenarios();
    },

    getScenario() { return this.scenario; },

    /** Returns current scenario definition (for debugging). */
    inspect() { return _scenarios[this.scenario]; },
  };

  window.fetch = async function mockFetch(url, opts) {
    if (typeof url !== 'string' || !url.includes('/api/cxdb/')) {
      return origFetch(url, opts);
    }

    const s = window.__mockCxdb.scenario;
    const def = _scenarios[s] || _scenarios['no_pipeline'];

    // Extract CXDB instance index from URL: /api/cxdb/{i}/...
    const instanceMatch = url.match(/\/api\/cxdb\/(\d+)\//);
    const instanceIdx = instanceMatch ? parseInt(instanceMatch[1], 10) : 0;

    // Handle unreachable mode
    if (def._mode === 'unreachable') {
      return new Response('Bad Gateway', { status: 502 });
    }

    // Handle partial connectivity: instance idx missing or null → 502
    if (def.contexts.hasOwnProperty(instanceIdx) && def.contexts[instanceIdx] === null) {
      return new Response('Bad Gateway', { status: 502 });
    }

    // CQL search endpoint
    if (url.includes('/contexts/search')) {
      if (def._mode === 'cql_404') {
        return new Response('Not Found', { status: 404 });
      }
      const ctxs = def.contexts[instanceIdx] || [];
      return jsonOk({ contexts: ctxs });
    }

    // Context list endpoint (fallback or supplemental)
    if (url.match(/\/v1\/contexts(\?|$)/)) {
      const ctxs = def.contexts[instanceIdx] || [];
      return jsonOk({ contexts: ctxs });
    }

    // Turns endpoint: /v1/contexts/{id}/turns?...
    const turnsMatch = url.match(/\/contexts\/([^/]+)\/turns/);
    if (turnsMatch) {
      const contextId = turnsMatch[1];
      const allTurns = def.turns[contextId] || [];

      if (url.includes('view=raw')) {
        // Discovery path: find the RunStarted turn and return its data as msgpack
        const runStarted = [...allTurns].find(
          t => t.declared_type === 'com.kilroy.attractor.RunStarted'
        );
        if (!runStarted) return jsonOk({ turns: [] });

        // CXDB raw view returns declared_type as {type_id: "..."} object
        // and msgpack payload uses numeric field IDs (1=run_id, 8=graph_name)
        const msgpackPayload = {};
        if (runStarted.data.graph_name) msgpackPayload[8] = runStarted.data.graph_name;
        if (runStarted.data.run_id) msgpackPayload[1] = runStarted.data.run_id;
        return jsonOk({
          turns: [{
            turn_id: runStarted.turn_id,
            declared_type: { type_id: runStarted.declared_type },
            depth: 0,
            bytes_b64: packMsgpack(msgpackPayload),
          }],
        });
      }

      // Status polling path: return typed turns (already newest-first)
      return jsonOk({ turns: allTurns });
    }

    // Unknown CXDB endpoint — pass through
    console.log(`[mock-cxdb] Unhandled CXDB URL (passing through): ${url}`);
    return origFetch(url, opts);
  };

  function jsonOk(data) {
    return new Response(JSON.stringify(data), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  console.log('[mock-cxdb] Installed. Current scenario:', window.__mockCxdb.scenario);
  console.log('[mock-cxdb] Available scenarios:', Object.keys(_scenarios).join(', '));
})();
