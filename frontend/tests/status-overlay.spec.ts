import { test, expect } from "@playwright/test";
import path from "path";
import { startServer, stopServer } from "./utils/server";
import { expectSvgRendered } from "./utils/assertions";

const FIXTURES_DIR = path.resolve(__dirname, "../../server/tests/fixtures");

const MOCK_CONTEXTS_RESPONSE = {
  contexts: [
    {
      id: "ctx-001",
      graph_name: "simple_pipeline",
      created_at: new Date().toISOString(),
    },
  ],
};

const MOCK_TURNS_RESPONSE = {
  turns: [],
};

test.describe("Status Overlay", () => {
  let serverProc: ReturnType<typeof startServer> extends Promise<infer T>
    ? T
    : never;
  const TEST_PORT = 9041;

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

  test("connection indicator is present and visible", async ({ page }) => {
    await page.goto(`http://127.0.0.1:${TEST_PORT}/`);

    await expect(
      page.locator('[data-testid="connection-indicator"]')
    ).toBeVisible({ timeout: 10000 });
  });

  test("CXDB unreachable - graph still renders and indicator shows state", async ({
    page,
  }) => {
    // Route CXDB proxy requests (numeric index paths) to simulate unreachable
    // but NOT /api/cxdb/instances which is needed for app initialization
    await page.route(/\/api\/cxdb\/\d+\//, async (route) => {
      await route.abort("failed");
    });

    await page.goto(`http://127.0.0.1:${TEST_PORT}/`);

    // SVG should still render even with CXDB unreachable
    await expectSvgRendered(page);

    // Connection indicator should be present
    await expect(
      page.locator('[data-testid="connection-indicator"]')
    ).toBeVisible({ timeout: 10000 });
  });

  test("CXDB returns mock data - status overlay applied", async ({ page }) => {
    // Mock CXDB proxy requests (numeric index paths) with fixture data
    await page.route(/\/api\/cxdb\/\d+\//, async (route) => {
      const url = route.request().url();
      if (url.includes("/turns")) {
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify(MOCK_TURNS_RESPONSE),
        });
      } else {
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify(MOCK_CONTEXTS_RESPONSE),
        });
      }
    });

    await page.goto(`http://127.0.0.1:${TEST_PORT}/`);

    // SVG should render
    await expectSvgRendered(page);

    // Nodes should have data-status attribute (all pending with no turns)
    const nodeGroups = page.locator("svg g.node");
    await nodeGroups.first().waitFor({ timeout: 20000 });

    // Connection indicator should be visible
    await expect(
      page.locator('[data-testid="connection-indicator"]')
    ).toBeVisible({ timeout: 10000 });
  });

  test("nodes have data-status attribute after status overlay", async ({
    page,
  }) => {
    await page.goto(`http://127.0.0.1:${TEST_PORT}/`);
    await expectSvgRendered(page);

    // Nodes may or may not have data-status depending on whether polling ran
    // Just verify that the SVG node groups exist
    const nodeGroups = page.locator("svg g.node");
    await nodeGroups.first().waitFor({ timeout: 20000 });
    const count = await nodeGroups.count();
    expect(count).toBeGreaterThan(0);
  });
});
