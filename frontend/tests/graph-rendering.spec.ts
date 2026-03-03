import { test, expect } from "@playwright/test";
import path from "path";
import { startServer, stopServer } from "./utils/server";
import {
  expectSvgRendered,
  expectTabBarVisible,
  expectTabVisible,
} from "./utils/assertions";

const FIXTURES_DIR = path.resolve(__dirname, "../../server/tests/fixtures");

test.describe("Graph Rendering", () => {
  let serverProc: ReturnType<typeof startServer> extends Promise<infer T>
    ? T
    : never;
  const TEST_PORT = 9040;

  test.beforeAll(async () => {
    serverProc = await startServer(
      ["--dot", path.join(FIXTURES_DIR, "simple-pipeline.dot")],
      TEST_PORT
    );
  });

  test.afterAll(async () => {
    stopServer(serverProc);
    await new Promise((r) => setTimeout(r, 300));
  });

  test("application loads and renders SVG from DOT", async ({ page }) => {
    await page.goto(`http://127.0.0.1:${TEST_PORT}/`);

    // Tab bar should be visible
    await expectTabBarVisible(page);

    // Tab should show the graph ID from the DOT file
    await expectTabVisible(page, "simple_pipeline");

    // SVG should render
    await expectSvgRendered(page);
  });

  test("graph area has data-testid attribute", async ({ page }) => {
    await page.goto(`http://127.0.0.1:${TEST_PORT}/`);

    // Wait for SVG to appear
    await expectSvgRendered(page);

    // graph-container is present
    await expect(
      page.locator('[data-testid="graph-container"]')
    ).toBeVisible({ timeout: 20000 });
  });

  test("tab bar renders with correct graph ID label", async ({ page }) => {
    await page.goto(`http://127.0.0.1:${TEST_PORT}/`);

    await expectTabBarVisible(page);

    // Tab label should use graph ID (simple_pipeline), not filename
    await expect(
      page.locator('[data-testid="tab-simple-pipeline.dot"]')
    ).toBeVisible({ timeout: 10000 });
  });

  test("node click opens detail panel", async ({ page }) => {
    await page.goto(`http://127.0.0.1:${TEST_PORT}/`);

    // Wait for SVG
    await expectSvgRendered(page);

    // Detail panel should not be visible initially
    await expect(page.locator('[data-testid="detail-panel"]')).not.toBeVisible({
      timeout: 5000,
    });

    // Click a node in the SVG
    const node = page.locator("svg g.node").first();
    await node.waitFor({ timeout: 20000 });
    await node.click();

    // Detail panel should now be visible
    await expect(page.locator('[data-testid="detail-panel"]')).toBeVisible({
      timeout: 5000,
    });
  });

  test("connection indicator is present", async ({ page }) => {
    await page.goto(`http://127.0.0.1:${TEST_PORT}/`);
    await expectTabBarVisible(page);

    await expect(
      page.locator('[data-testid="connection-indicator"]')
    ).toBeVisible({ timeout: 5000 });
  });
});
