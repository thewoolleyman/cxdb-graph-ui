/**
 * TabBar — renders pipeline tabs.
 */
import React, { useCallback } from "react";
import type { Pipeline } from "@/types/index";

interface TabBarProps {
  pipelines: Pipeline[];
  activePipeline: string | null;
  onSelectPipeline: (filename: string) => void;
  children?: React.ReactNode;
}

export function TabBar({
  pipelines,
  activePipeline,
  onSelectPipeline,
  children,
}: TabBarProps): React.ReactElement {
  return (
    <div
      className="flex items-center border-b border-gray-200 bg-white px-2"
      data-testid="tab-bar"
    >
      <div className="flex flex-1 gap-1 overflow-x-auto py-1">
        {pipelines.map((pipeline) => {
          const label = pipeline.graphId ?? pipeline.filename;
          const isActive = pipeline.filename === activePipeline;
          return (
            <TabButton
              key={pipeline.filename}
              label={label}
              isActive={isActive}
              onClick={() => onSelectPipeline(pipeline.filename)}
              testId={`tab-${pipeline.filename}`}
            />
          );
        })}
      </div>
      {children}
    </div>
  );
}

interface TabButtonProps {
  label: string;
  isActive: boolean;
  onClick: () => void;
  testId?: string;
}

function TabButton({
  label,
  isActive,
  onClick,
  testId,
}: TabButtonProps): React.ReactElement {
  const handleClick = useCallback(() => onClick(), [onClick]);

  return (
    <button
      type="button"
      onClick={handleClick}
      data-testid={testId}
      className={[
        "rounded px-3 py-1.5 text-sm font-medium whitespace-nowrap transition-colors",
        isActive
          ? "bg-blue-100 text-blue-700"
          : "text-gray-600 hover:bg-gray-100 hover:text-gray-800",
      ].join(" ")}
    >
      {/* textContent-safe: use span with no innerHTML */}
      <span>{label}</span>
    </button>
  );
}
