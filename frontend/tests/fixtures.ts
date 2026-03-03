import { test as base } from "@playwright/test";
import { ChildProcess } from "child_process";
import path from "path";
import { startServer, stopServer } from "./utils/server";

export type ServerFixture = {
  serverProcess: ChildProcess;
  serverPort: number;
};

const FIXTURES_DIR = path.resolve(__dirname, "../../server/tests/fixtures");

// Allocate unique ports per worker to avoid conflicts
let portCounter = 9031;
function allocatePort(): number {
  return portCounter++;
}

export const test = base.extend<ServerFixture>({
  serverProcess: [
    async ({ serverPort }, use) => {
      const dotPath = path.join(FIXTURES_DIR, "simple-pipeline.dot");
      const proc = await startServer(["--dot", dotPath], serverPort);
      await use(proc);
      stopServer(proc);
      await new Promise((r) => setTimeout(r, 300));
    },
    { auto: false },
  ],
  serverPort: [
    async ({}, use) => {
      const port = allocatePort();
      await use(port);
    },
    { auto: false },
  ],
});

export { expect } from "@playwright/test";
