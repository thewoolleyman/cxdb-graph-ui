import { Page, expect } from "@playwright/test";

export async function expectSvgRendered(page: Page): Promise<void> {
  await expect(page.locator("svg")).toBeVisible({ timeout: 20000 });
}

export async function expectTabBarVisible(page: Page): Promise<void> {
  await expect(page.locator('[data-testid="tab-bar"]')).toBeVisible({
    timeout: 10000,
  });
}

export async function expectTabVisible(
  page: Page,
  label: string
): Promise<void> {
  await expect(page.locator('[data-testid="tab-bar"]')).toContainText(label, {
    timeout: 10000,
  });
}
