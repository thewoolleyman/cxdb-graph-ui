import { test, expect } from "@playwright/test";
import path from "path";
import { startServer, stopServer } from "./utils/server";
import { expectSvgRendered } from "./utils/assertions";

const FIXTURES_DIR = path.resolve(__dirname, "../../server/tests/fixtures");

test.describe("Detail Panel", () => {
  let serverProc: ReturnType<typeof startServer> extends Promise<infer T>
    ? T
    : never;
  const TEST_PORT = 9042;

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

  test("detail panel is not visible before node click", async ({ page }) => {
    await page.goto(`http://127.0.0.1:${TEST_PORT}/`);

    // Wait for the app to load
    await expectSvgRendered(page);

    // Detail panel should not be visible
    await expect(
      page.locator('[data-testid="detail-panel"]')
    ).not.toBeVisible({ timeout: 5000 });
  });

  test("clicking a node opens the detail panel", async ({ page }) => {
    await page.goto(`http://127.0.0.1:${TEST_PORT}/`);

    await expectSvgRendered(page);

    // Click the first SVG node
    const node = page.locator("svg g.node").first();
    await node.waitFor({ timeout: 20000 });
    await node.click();

    // Detail panel should now be visible
    await expect(page.locator('[data-testid="detail-panel"]')).toBeVisible({
      timeout: 5000,
    });
  });

  test("detail panel shows node ID", async ({ page }) => {
    await page.goto(`http://127.0.0.1:${TEST_PORT}/`);

    await expectSvgRendered(page);

    // Click the first node
    const node = page.locator("svg g.node").first();
    await node.waitFor({ timeout: 20000 });
    await node.click();

    // Detail panel should show node ID
    await expect(
      page.locator('[data-testid="detail-node-id"]')
    ).toBeVisible({ timeout: 5000 });

    const nodeIdText = await page
      .locator('[data-testid="detail-node-id"]')
      .textContent();
    expect(nodeIdText).toBeTruthy();
    expect(nodeIdText!.length).toBeGreaterThan(0);
  });

  test("close button hides the detail panel", async ({ page }) => {
    await page.goto(`http://127.0.0.1:${TEST_PORT}/`);

    await expectSvgRendered(page);

    // Click the first node to open panel
    const node = page.locator("svg g.node").first();
    await node.waitFor({ timeout: 20000 });
    await node.click();

    // Panel should be visible
    await expect(page.locator('[data-testid="detail-panel"]')).toBeVisible({
      timeout: 5000,
    });

    // Click the close button
    await page.locator('[data-testid="detail-close"]').click();

    // Panel should be hidden
    await expect(
      page.locator('[data-testid="detail-panel"]')
    ).not.toBeVisible({ timeout: 5000 });
  });
});
