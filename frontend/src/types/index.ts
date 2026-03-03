// Node execution status
export type NodeStatusValue =
  | "pending"
  | "running"
  | "complete"
  | "error"
  | "stale";

// Per-node status tracking
export interface NodeStatus {
  status: NodeStatusValue;
  lastTurnId: string | null;
  toolName: string | null;
  turnCount: number;
  errorCount: number;
  hasLifecycleResolution: boolean;
}

// Status map: nodeId -> NodeStatus
export type StatusMap = Map<string, NodeStatus>;

// Per-context known mapping result
export interface KnownMapping {
  graphName: string;
  runId: string;
}

// Context info from CXDB
export interface ContextInfo {
  context_id: string;
  head_depth: number;
  head_turn_id: string;
  created_at_unix_ms: number;
  is_live: boolean;
  client_tag: string | null;
}

// CQL search response
export interface CqlSearchResponse {
  contexts: ContextInfo[];
  total_count: number;
  elapsed_ms: number;
  query: string;
}

// Context list response
export interface ContextListResponse {
  contexts: ContextInfo[];
  count?: number;
  active_sessions?: unknown[];
  active_tags?: string[];
}

// Turn declared type
export interface DeclaredType {
  type_id: string;
  type_version: number;
}

// Turn data (partial — different fields for different types)
export interface TurnData {
  node_id?: string;
  run_id?: string;
  graph_name?: string;
  text?: string;
  tool_name?: string;
  arguments_json?: string;
  output?: string;
  is_error?: boolean;
  call_id?: string;
  model?: string;
  input_tokens?: number;
  output_tokens?: number;
  tool_use_count?: number;
  status?: string;
  preferred_label?: string;
  failure_reason?: string;
  notes?: string;
  suggested_next_ids?: string[];
  will_retry?: boolean;
  attempt?: number;
  delay_ms?: number;
  final_status?: string;
  final_git_commit_sha?: string;
  reason?: string;
  question_text?: string;
  question_type?: string;
  answer_value?: string;
  duration_ms?: number;
  handler_type?: string;
  branch_count?: number;
  join_policy?: string;
  error_policy?: string;
  branch_key?: string;
  branch_index?: number;
  success_count?: number;
  failure_count?: number;
  git_commit_sha?: string;
  // raw view fields
  bytes_b64?: string;
}

// Turn response item
export interface TurnItem {
  turn_id: string;
  parent_turn_id: string | null;
  depth: number;
  declared_type: DeclaredType;
  decoded_as?: DeclaredType;
  data: TurnData;
  // raw view
  bytes_b64?: string;
}

// Turn fetch response
export interface TurnResponse {
  meta: {
    context_id: string;
    head_depth: number;
    head_turn_id: string;
    registry_bundle_id?: string;
  };
  turns: TurnItem[];
  next_before_turn_id: string | null;
}

// Parsed DOT node attributes (from server /nodes endpoint)
export interface NodeAttrs {
  shape: string | null;
  class: string | null;
  prompt: string | null;
  tool_command: string | null;
  question: string | null;
  goal_gate: string | null;
}

// Parsed edge (from server /edges endpoint)
export interface EdgeInfo {
  source: string;
  target: string;
  label: string | null;
}

// Pipeline information
export interface Pipeline {
  filename: string;
  graphId: string | null;
}

// Active context for a pipeline
export interface ActiveContext {
  cxdbIndex: number;
  contextId: string;
  runId: string;
}

// CXDB instance reachability status
export type InstanceStatus = "ok" | "unreachable" | "unknown";
