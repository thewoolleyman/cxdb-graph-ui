import { execSync } from "child_process";
import path from "path";

async function globalSetup() {
  const repoRoot = path.resolve(__dirname, "../../");
  const serverDir = path.join(repoRoot, "server");
  console.log("Building Rust server for E2E tests...");
  // CARGO_TARGET_DIR is inherited from the shell environment (set by Kilroy worktree)
  execSync("cargo build", {
    cwd: serverDir,
    stdio: "inherit",
    env: { ...process.env },
  });
  console.log("Rust server build complete.");
}

export default globalSetup;
