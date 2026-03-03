import { ChildProcess, spawn, execSync } from "child_process";
import path from "path";
import net from "net";

// Use CARGO_TARGET_DIR env var if set (set by Kilroy worktree environment),
// otherwise fall back to the conventional location relative to server/
function resolveServerBinary(): string {
  const cargoTargetDir = process.env.CARGO_TARGET_DIR;
  if (cargoTargetDir) {
    return path.join(cargoTargetDir, "debug", "cxdb-graph-ui");
  }
  return path.resolve(__dirname, "../../../server/target/debug/cxdb-graph-ui");
}

export const SERVER_BINARY = resolveServerBinary();

export async function waitForPort(
  port: number,
  timeout = 15000
): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    try {
      await new Promise<void>((resolve, reject) => {
        const socket = net.connect(port, "127.0.0.1");
        socket.on("connect", () => {
          socket.destroy();
          resolve();
        });
        socket.on("error", reject);
      });
      return;
    } catch {
      await new Promise((r) => setTimeout(r, 100));
    }
  }
  throw new Error(`Port ${port} not ready after ${timeout}ms`);
}

export async function startServer(
  args: string[],
  port = 9031
): Promise<ChildProcess> {
  const proc = spawn(SERVER_BINARY, ["--port", String(port), ...args], {
    stdio: ["ignore", "pipe", "pipe"],
  });
  proc.stdout?.on("data", (d: Buffer) => process.stdout.write(d));
  proc.stderr?.on("data", (d: Buffer) => process.stderr.write(d));
  await waitForPort(port);
  return proc;
}

export function stopServer(proc: ChildProcess): void {
  proc.kill("SIGTERM");
}
