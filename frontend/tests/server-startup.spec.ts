import { test, expect } from "@playwright/test";
import { spawnSync } from "child_process";
import { writeFileSync, mkdtempSync } from "fs";
import { tmpdir } from "os";
import path from "path";
import {
  SERVER_BINARY,
  startServer,
  stopServer,
  waitForPort,
} from "./utils/server";

const FIXTURES_DIR = path.resolve(__dirname, "../../server/tests/fixtures");

test.describe("Server Startup Validation", () => {
  test("server exits non-zero with no --dot flag", () => {
    const result = spawnSync(SERVER_BINARY, ["--port", "9099"], {
      timeout: 5000,
      encoding: "utf8",
      env: { ...process.env },
    });

    // Should exit with non-zero (clap marks --dot as required)
    expect(result.status).not.toBe(0);
  });

  test("server exits non-zero with duplicate basenames", () => {
    const dotPath = path.join(FIXTURES_DIR, "simple-pipeline.dot");

    const result = spawnSync(
      SERVER_BINARY,
      ["--port", "9098", "--dot", dotPath, "--dot", dotPath],
      {
        timeout: 5000,
        encoding: "utf8",
        env: { ...process.env },
      }
    );

    expect(result.status).not.toBe(0);
    const stderr = result.stderr ?? "";
    // Should mention duplicate in error
    expect(stderr.toLowerCase()).toMatch(/duplicate|error/);
  });

  test("server exits non-zero for anonymous graph (no named graph ID)", () => {
    const dir = mkdtempSync(path.join(tmpdir(), "e2e-test-"));
    const anonDot = path.join(dir, "anon.dot");
    writeFileSync(anonDot, "digraph { start [shape=Msquare] }");

    const result = spawnSync(
      SERVER_BINARY,
      ["--port", "9097", "--dot", anonDot],
      {
        timeout: 5000,
        encoding: "utf8",
        env: { ...process.env },
      }
    );

    expect(result.status).not.toBe(0);
    // stdout or stderr should contain the error
    const output = (result.stderr ?? "") + (result.stdout ?? "");
    expect(output.toLowerCase()).toMatch(/anonymous|error|named/);
  });

  test("valid invocation starts server successfully", async () => {
    const dotPath = path.join(FIXTURES_DIR, "simple-pipeline.dot");
    const TEST_PORT = 9044;

    const proc = await startServer(["--dot", dotPath], TEST_PORT);
    try {
      // Server is up - verify the port is responding
      await waitForPort(TEST_PORT, 2000);
      expect(proc.killed).toBe(false);
      expect(proc.exitCode).toBeNull();
    } finally {
      stopServer(proc);
      await new Promise((r) => setTimeout(r, 300));
    }
  });

  test("server serves /api/dots endpoint with correct shape", async () => {
    const dotPath = path.join(FIXTURES_DIR, "simple-pipeline.dot");
    const TEST_PORT = 9045;

    const proc = await startServer(["--dot", dotPath], TEST_PORT);
    try {
      const response = await fetch(`http://127.0.0.1:${TEST_PORT}/api/dots`);
      expect(response.ok).toBe(true);
      const data = (await response.json()) as { dots: string[] };
      expect(Array.isArray(data.dots)).toBe(true);
      expect(data.dots).toContain("simple-pipeline.dot");
    } finally {
      stopServer(proc);
      await new Promise((r) => setTimeout(r, 300));
    }
  });

  test("server serves /api/cxdb/instances endpoint with correct shape", async () => {
    const dotPath = path.join(FIXTURES_DIR, "simple-pipeline.dot");
    const TEST_PORT = 9046;

    const proc = await startServer(["--dot", dotPath], TEST_PORT);
    try {
      const response = await fetch(
        `http://127.0.0.1:${TEST_PORT}/api/cxdb/instances`
      );
      expect(response.ok).toBe(true);
      const data = (await response.json()) as { instances: string[] };
      expect(Array.isArray(data.instances)).toBe(true);
    } finally {
      stopServer(proc);
      await new Promise((r) => setTimeout(r, 300));
    }
  });
});
