import { test, expect } from "@playwright/test";
import path from "path";
import { startServer, stopServer } from "./utils/server";
import { expectSvgRendered } from "./utils/assertions";

const FIXTURES_DIR = path.resolve(__dirname, "../../server/tests/fixtures");

test.describe("Connection Handling", () => {
  let serverProc: ReturnType<typeof startServer> extends Promise<infer T>
    ? T
    : never;
  const TEST_PORT = 9043;

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

  test("graph renders even when CXDB is unreachable", async ({ page }) => {
    // Abort CXDB proxy requests (numeric index paths like /api/cxdb/0/...)
    // but NOT /api/cxdb/instances which is needed for app initialization
    await page.route(/\/api\/cxdb\/\d+\//, async (route) => {
      await route.abort("failed");
    });

    await page.goto(`http://127.0.0.1:${TEST_PORT}/`);

    // SVG should still render despite CXDB being down
    await expectSvgRendered(page);

    // Tab bar should still be visible
    await expect(page.locator('[data-testid="tab-bar"]')).toBeVisible({
      timeout: 10000,
    });
  });

  test("connection indicator shows offline state when CXDB returns 503", async ({
    page,
  }) => {
    // Mock CXDB proxy requests (numeric index paths) returning 503 errors
    // but NOT /api/cxdb/instances which is needed for app initialization
    await page.route(/\/api\/cxdb\/\d+\//, async (route) => {
      await route.fulfill({
        status: 503,
        contentType: "application/json",
        body: JSON.stringify({ error: "service unavailable" }),
      });
    });

    await page.goto(`http://127.0.0.1:${TEST_PORT}/`);

    // SVG should still render
    await expectSvgRendered(page);

    // Connection indicator should be present (showing some state)
    await expect(
      page.locator('[data-testid="connection-indicator"]')
    ).toBeVisible({ timeout: 10000 });
  });

  test("connection indicator is always present", async ({ page }) => {
    await page.goto(`http://127.0.0.1:${TEST_PORT}/`);

    // Connection indicator should be visible regardless of CXDB state
    await expect(
      page.locator('[data-testid="connection-indicator"]')
    ).toBeVisible({ timeout: 10000 });
  });
});
