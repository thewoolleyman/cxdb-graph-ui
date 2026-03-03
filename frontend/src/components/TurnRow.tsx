/**
 * TurnRow — renders a single CXDB turn in the detail panel.
 */
import React, { useState, useCallback } from "react";
import type { TurnItem } from "@/types/index";
import { formatMilliseconds } from "@/lib/utils";

const MAX_PREVIEW_CHARS = 500;
const MAX_PREVIEW_LINES = 8;
const MAX_EXPAND_CHARS = 8000;

function truncate(text: string, maxChars: number, maxLines: number): string {
  const lines = text.split("\n");
  if (lines.length > maxLines) {
    return lines.slice(0, maxLines).join("\n");
  }
  if (text.length > maxChars) {
    return text.slice(0, maxChars);
  }
  return text;
}

function getTypeShortName(typeId: string): string {
  const parts = typeId.split(".");
  return parts[parts.length - 1] ?? typeId;
}

interface OutputResult {
  text: string;
  isError: boolean;
  isFixed: boolean;
}

function getOutput(turn: TurnItem): OutputResult {
  const typeId = turn.declared_type.type_id;
  const d = turn.data;
  const shortType = getTypeShortName(typeId);

  switch (shortType) {
    case "Prompt":
      return { text: d.text ?? "", isError: false, isFixed: false };
    case "ToolCall":
      return {
        text: d.arguments_json ?? "",
        isError: false,
        isFixed: false,
      };
    case "ToolResult":
      return {
        text: d.output ?? "",
        isError: d.is_error === true,
        isFixed: false,
      };
    case "AssistantMessage":
      return { text: d.text ?? "", isError: false, isFixed: false };
    case "StageStarted": {
      const handlerPart =
        d.handler_type && d.handler_type.length > 0
          ? `: ${d.handler_type}`
          : "";
      return {
        text: `Stage started${handlerPart}`,
        isError: false,
        isFixed: true,
      };
    }
    case "StageFinished": {
      let text = `Stage finished: ${d.status ?? ""}`;
      if (d.preferred_label && d.preferred_label.length > 0) {
        text += ` — ${d.preferred_label}`;
      }
      if (d.failure_reason && d.failure_reason.length > 0) {
        text += `\n${d.failure_reason}`;
      }
      if (d.notes && d.notes.length > 0) {
        text += `\n${d.notes}`;
      }
      if (d.suggested_next_ids && d.suggested_next_ids.length > 0) {
        text += `\nNext: ${d.suggested_next_ids.join(", ")}`;
      }
      return {
        text,
        isError: d.status === "fail",
        isFixed: true,
      };
    }
    case "StageFailed": {
      let text = d.failure_reason ?? "";
      if (d.will_retry === true) {
        text += ` (will retry, attempt ${d.attempt ?? ""})`;
      } else if (d.attempt !== undefined && d.attempt > 0) {
        text += ` (attempt ${d.attempt})`;
      }
      return { text, isError: d.will_retry !== true, isFixed: true };
    }
    case "StageRetrying": {
      let text = `Retrying (attempt ${d.attempt ?? ""}`;
      if (d.delay_ms !== undefined && d.delay_ms > 0) {
        text += `, delay ${formatMilliseconds(d.delay_ms)}`;
      }
      text += ")";
      return { text, isError: false, isFixed: true };
    }
    case "RunCompleted":
      return {
        text: d.final_status ?? "",
        isError: false,
        isFixed: true,
      };
    case "RunFailed":
      return { text: d.reason ?? "", isError: true, isFixed: true };
    case "InterviewStarted": {
      let text = d.question_text ?? "";
      if (d.question_type && d.question_type.length > 0) {
        text += ` [${d.question_type}]`;
      }
      return { text, isError: false, isFixed: true };
    }
    case "InterviewCompleted": {
      let text = d.answer_value ?? "";
      if (d.duration_ms !== undefined && d.duration_ms > 0) {
        text += ` (waited ${formatMilliseconds(d.duration_ms)})`;
      }
      return { text, isError: false, isFixed: true };
    }
    case "InterviewTimeout":
      return {
        text: d.question_text ?? "",
        isError: true,
        isFixed: true,
      };
    default:
      return { text: "[unsupported turn type]", isError: false, isFixed: true };
  }
}

function getTool(turn: TurnItem): string {
  const shortType = getTypeShortName(turn.declared_type.type_id);
  switch (shortType) {
    case "ToolCall":
    case "ToolResult":
      return turn.data.tool_name ?? "";
    case "AssistantMessage":
      return turn.data.model ?? "";
    default:
      return "";
  }
}

interface TurnRowProps {
  turn: TurnItem;
}

export function TurnRow({ turn }: TurnRowProps): React.ReactElement {
  const [expanded, setExpanded] = useState(false);
  const { text, isError, isFixed } = getOutput(turn);
  const typeName = getTypeShortName(turn.declared_type.type_id);
  const tool = getTool(turn);

  const previewText = isFixed
    ? text
    : truncate(text, MAX_PREVIEW_CHARS, MAX_PREVIEW_LINES);
  const isTruncated = !isFixed && previewText !== text;

  const expandedText =
    text.length > MAX_EXPAND_CHARS ? text.slice(0, MAX_EXPAND_CHARS) : text;
  const isCappedOnExpand = text.length > MAX_EXPAND_CHARS;

  const displayText = expanded ? expandedText : previewText;

  const toggleExpand = useCallback(() => setExpanded((v) => !v), []);

  return (
    <tr
      className={[
        "border-b border-gray-100 align-top text-xs",
        isError ? "bg-red-50" : "",
      ].join(" ")}
      data-testid="turn-row"
    >
      <td className="p-1 font-mono text-gray-500 whitespace-nowrap">
        {typeName}
      </td>
      <td className="p-1 text-gray-600 whitespace-nowrap">{tool}</td>
      <td className="p-1">
        {isError && (
          <span className="mr-1 inline-block rounded bg-red-100 px-1 py-0.5 text-xs text-red-700">
            error
          </span>
        )}
        <pre
          className="whitespace-pre-wrap break-words font-mono text-xs text-gray-700"
          style={{ maxWidth: "400px" }}
        >
          {displayText}
        </pre>
        {isTruncated && !expanded && (
          <button
            type="button"
            onClick={toggleExpand}
            className="mt-0.5 text-xs text-blue-500 hover:underline"
          >
            Show more
          </button>
        )}
        {expanded && (
          <>
            {isCappedOnExpand && (
              <div className="mt-0.5 text-xs text-gray-400">
                (truncated to 8,000 characters — full content available in CXDB)
              </div>
            )}
            <button
              type="button"
              onClick={toggleExpand}
              className="mt-0.5 text-xs text-blue-500 hover:underline"
            >
              Show less
            </button>
          </>
        )}
      </td>
    </tr>
  );
}
