import fs from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright-core";

const required = (name, fallback = "") => {
    const value = process.env[name] || fallback;
    if (!value) throw new Error(`Missing required environment variable: ${name}`);
    return value;
};

const baseUrl = required("FACODI_BROWSER_BASE_URL", "http://127.0.0.1:8069").replace(/\/$/, "");
const executablePath = required("FACODI_BROWSER_CHROME_BIN");
const screenshotDir = required("FACODI_BROWSER_SCREENSHOT_DIR");
const courseRoute = required("FACODI_BROWSER_COURSE_ROUTE");
const roadmapRoute = required("FACODI_BROWSER_ROADMAP_ROUTE");
const unitRoute = required("FACODI_BROWSER_UNIT_ROUTE");
const moduleRoute = required("FACODI_BROWSER_MODULE_ROUTE");

await fs.mkdir(screenshotDir, { recursive: true });

const viewports = {
    desktop: { width: 1440, height: 1100 },
    mobile: { width: 390, height: 844 },
    narrow: { width: 320, height: 700 },
};

// Keep runtime acceptance intentionally small. Repository/unit contracts own
// implementation detail; this browser gate only proves the key user journeys
// render, stay inside the viewport and expose their stable semantic hooks.
const publicCases = [
    {
        name: "courses",
        route: "/courses",
        selectors: [".facodi-learning-catalogue-hero", ".facodi-index-tabs--courses"],
        sizes: ["desktop", "mobile", "narrow"],
        mobileMenu: true,
    },
    {
        name: "roadmaps",
        route: "/roadmaps",
        selectors: [".facodi-learning-hero"],
        sizes: ["desktop", "mobile"],
    },
    {
        name: "units",
        route: "/curricular-units",
        selectors: [".facodi-filter-sheet"],
        sizes: ["desktop", "mobile"],
    },
    {
        name: "explore-content",
        route: "/explore/content",
        selectors: ['[data-facodi-explore-workbench="1"]'],
        sizes: ["desktop", "mobile"],
    },
];

const detailCases = [
    { name: "course", route: courseRoute, selector: ".facodi-course-study-shell" },
    { name: "roadmap-detail", route: roadmapRoute, selector: ".facodi-roadmap-study-path" },
    { name: "unit-detail", route: unitRoute, selector: ".facodi-unit-layout" },
    { name: "module-detail", route: moduleRoute, selector: ".facodi-module-detail" },
];

const browser = await chromium.launch({
    executablePath,
    headless: true,
    args: ["--no-sandbox", "--disable-dev-shm-usage"],
});

const assertViewport = async (page, label) => {
    const state = await page.evaluate(() => ({
        scrollWidth: document.documentElement.scrollWidth,
        viewportWidth: window.innerWidth,
    }));
    if (state.scrollWidth > state.viewportWidth + 1) {
        throw new Error(
            `${label}: page-level horizontal overflow ${state.scrollWidth}px > ${state.viewportWidth}px`
        );
    }
};

const openPage = async (context, route, label) => {
    const page = await context.newPage();
    const response = await page.goto(baseUrl + route, {
        waitUntil: "domcontentloaded",
        timeout: 30000,
    });
    if (!response || response.status() >= 400) {
        throw new Error(`${label}: HTTP ${response ? response.status() : "no response"}`);
    }
    const bodyText = (await page.locator("body").innerText()).trim();
    if (!bodyText) throw new Error(`${label}: body text is empty`);
    return page;
};

try {
    for (const testCase of publicCases) {
        for (const sizeName of testCase.sizes) {
            const viewport = viewports[sizeName];
            const context = await browser.newContext({ viewport });
            const label = `${testCase.name} ${sizeName}`;
            const page = await openPage(context, testCase.route, label);

            for (const selector of testCase.selectors) {
                await page.locator(selector).first().waitFor({ state: "visible", timeout: 5000 });
            }
            await assertViewport(page, label);

            if (testCase.mobileMenu && viewport.width <= 390) {
                const toggle = page.locator('[data-bs-target="#top_menu_collapse_mobile"]').first();
                await toggle.waitFor({ state: "visible", timeout: 5000 });
                await toggle.click();
                await page.locator("#top_menu_collapse_mobile").waitFor({ state: "visible", timeout: 5000 });
            }

            await page.screenshot({
                path: path.join(screenshotDir, `${testCase.name}-${sizeName}.png`),
                fullPage: true,
            });
            console.log(`PASS ${label} ${viewport.width}x${viewport.height}`);
            await context.close();
        }
    }

    // Detail pages get one desktop smoke each. Their rendering contracts are
    // already covered by addon tests, so duplicating every breakpoint here
    // adds time without improving release confidence.
    for (const testCase of detailCases) {
        const context = await browser.newContext({ viewport: viewports.desktop });
        const page = await openPage(context, testCase.route, testCase.name);
        await page.locator(testCase.selector).first().waitFor({ state: "visible", timeout: 5000 });
        await assertViewport(page, testCase.name);
        console.log(`PASS ${testCase.name} desktop`);
        await context.close();
    }

    // One authenticated mobile smoke proves the canonical portal renders and
    // keeps the native Odoo toolbox. Avoid copy assertions so translations can
    // evolve without breaking the deployment gate.
    {
        const context = await browser.newContext({ viewport: viewports.mobile });
        const page = await context.newPage();
        await page.goto(baseUrl + "/web/login?redirect=/my/home", {
            waitUntil: "domcontentloaded",
            timeout: 30000,
        });
        await page.locator('input[name="login"]').fill("admin");
        await page.locator('input[name="password"]').fill("facodi-ci-admin");
        await Promise.all([
            page.waitForURL(/\/my\/home/, { timeout: 30000 }),
            page.locator('form.oe_login_form button[type="submit"]').click(),
        ]);

        for (const selector of [
            '[data-facodi-portal-home="1"]',
            '[data-facodi-campus-card="1"]',
            ".facodi-portal-board",
            '[data-facodi-academic-map="1"]',
            '[data-facodi-campus-pulse="1"]',
            ".facodi-portal-toolbox-heading",
            ".o_portal_docs",
        ]) {
            await page.locator(selector).first().waitFor({ state: "visible", timeout: 5000 });
        }

        const legacyPortalResponse = await context.request.get(baseUrl + "/minha-facodi", {
            maxRedirects: 0,
        });
        if (legacyPortalResponse.status() !== 301) {
            throw new Error(
                `portal: /minha-facodi must return permanent 301, got ${legacyPortalResponse.status()}`
            );
        }
        if (!(legacyPortalResponse.headers()["location"] || "").endsWith("/my/home")) {
            throw new Error("portal: /minha-facodi must redirect to /my/home");
        }

        await assertViewport(page, "portal mobile");
        await page.screenshot({
            path: path.join(screenshotDir, "portal-home-mobile.png"),
            fullPage: true,
        });
        console.log("PASS portal-home mobile 390x844");
        await context.close();
    }
} finally {
    await browser.close();
}
