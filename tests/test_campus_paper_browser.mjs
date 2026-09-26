import fs from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright-core";

const required = (name, fallback = "") => {
    const value = process.env[name] || fallback;
    if (!value) {
        throw new Error(`Missing required environment variable: ${name}`);
    }
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
    desktop: { width: 1440, height: 1200 },
    tablet: { width: 1024, height: 1366 },
    mobile: { width: 390, height: 844 },
    narrow: { width: 320, height: 700 },
};

const cases = [
    {
        name: "slides",
        route: "/slides",
        sizes: ["desktop", "mobile", "narrow"],
        selectors: [".facodi-learning-catalogue-hero", ".facodi-index-tabs--courses", ".facodi-course-record-card"],
        mobileMenu: true,
    },
    {
        name: "course",
        route: courseRoute,
        sizes: ["desktop", "mobile"],
        selectors: [".facodi-course-study-shell", ".facodi-course-alignment-sheet"],
    },
    {
        name: "roadmaps",
        route: "/roadmaps",
        sizes: ["desktop", "mobile"],
        selectors: [".facodi-learning-hero", ".facodi-record-card--roadmap"],
    },
    {
        name: "roadmap-detail",
        route: roadmapRoute,
        sizes: ["desktop", "mobile"],
        selectors: [".facodi-roadmap-study-path"],
    },
    {
        name: "units",
        route: "/unidades-curriculares",
        sizes: ["desktop", "mobile", "narrow"],
        selectors: [".facodi-filter-sheet", ".facodi-record-card--unit"],
    },
    {
        name: "unit-detail",
        route: unitRoute,
        sizes: ["desktop", "mobile", "narrow"],
        selectors: [".facodi-unit-layout", ".facodi-reference-rail", ".facodi-module-stack"],
    },
    {
        name: "module-detail",
        route: moduleRoute,
        sizes: ["desktop", "mobile"],
        selectors: [".facodi-module-detail"],
    },
];

const browser = await chromium.launch({
    executablePath,
    headless: true,
    args: ["--no-sandbox", "--disable-dev-shm-usage"],
});

try {
    for (const testCase of cases) {
        for (const sizeName of testCase.sizes) {
            const viewport = viewports[sizeName];
            const context = await browser.newContext({ viewport });
            const page = await context.newPage();
            const response = await page.goto(baseUrl + testCase.route, {
                waitUntil: "domcontentloaded",
                timeout: 30000,
            });
            if (!response || response.status() >= 400) {
                throw new Error(
                    `${testCase.name} ${sizeName}: HTTP ${response ? response.status() : "no response"}`
                );
            }

            await page.waitForLoadState("networkidle", { timeout: 5000 }).catch(() => {});

            const bodyText = (await page.locator("body").innerText()).trim();
            if (!bodyText) {
                throw new Error(`${testCase.name} ${sizeName}: body text is empty`);
            }

            for (const selector of testCase.selectors) {
                const locator = page.locator(selector).first();
                if ((await locator.count()) < 1) {
                    throw new Error(`${testCase.name} ${sizeName}: missing selector ${selector}`);
                }
            }

            const overflow = await page.evaluate(() => ({
                scrollWidth: document.documentElement.scrollWidth,
                viewportWidth: window.innerWidth,
                overflow: document.documentElement.scrollWidth > window.innerWidth + 1,
            }));
            if (overflow.overflow) {
                throw new Error(
                    `${testCase.name} ${sizeName}: page-level horizontal overflow ${overflow.scrollWidth}px > ${overflow.viewportWidth}px`
                );
            }

            if (testCase.mobileMenu && viewport.width <= 390) {
                const toggle = page.locator('[data-bs-target="#top_menu_collapse_mobile"]').first();
                if ((await toggle.count()) < 1) {
                    throw new Error(`${testCase.name} ${sizeName}: native Odoo mobile menu toggle missing`);
                }
                await toggle.click();
                const mobileMenu = page.locator("#top_menu_collapse_mobile");
                await mobileMenu.waitFor({ state: "visible", timeout: 5000 });
            }

            const screenshotPath = path.join(screenshotDir, `${testCase.name}-${sizeName}.png`);
            await page.screenshot({ path: screenshotPath, fullPage: true });
            console.log(
                `PASS ${testCase.name} ${sizeName} ${viewport.width}x${viewport.height}`
            );
            await context.close();
        }
    }

    for (const sizeName of ["desktop", "mobile"]) {
        const viewport = viewports[sizeName];
        const context = await browser.newContext({ viewport });
        const page = await context.newPage();
        await page.goto(baseUrl + "/web/login?redirect=/my/home", {
            waitUntil: "domcontentloaded",
            timeout: 30000,
        });
        await page.locator('input[name="login"]').fill("admin");
        await page.locator('input[name="password"]').fill("facodi-ci-admin");
        await Promise.all([
            page.waitForURL(/\/my\/home/, { timeout: 30000 }),
            page.locator('button[type="submit"]').click(),
        ]);
        await page.waitForLoadState("networkidle", { timeout: 5000 }).catch(() => {});

        for (const selector of [
            '[data-facodi-portal-home="1"]',
            '[data-facodi-campus-card="1"]',
            ".facodi-momentum-strip",
            ".facodi-portal-board",
            '[data-facodi-academic-map="1"]',
            '[data-facodi-campus-pulse="1"]',
            '[data-facodi-latest-wins="1"]',
            ".facodi-academic-map__unit",
            ".facodi-latest-wins",
            ".o_portal_docs",
        ]) {
            if ((await page.locator(selector).count()) < 1) {
                throw new Error(`portal ${sizeName}: missing selector ${selector}`);
            }
        }

        const pulse = page.locator('[data-facodi-campus-pulse="1"]').first();
        const pulsePost = pulse.locator(".facodi-campus-pulse__post").first();
        const pulseEmpty = pulse.locator('[data-facodi-empty-state="1"]').first();
        if ((await pulsePost.count()) < 1 && (await pulseEmpty.count()) < 1) {
            throw new Error(
                `portal ${sizeName}: Campus pulse rendered neither a forum post nor its empty state`
            );
        }

        const bodyText = await page.locator("body").innerText();
        for (const marker of [
            "Your campus",
            "Your learning shelf",
            "See where FACODI can take you next",
            "Campus pulse",
            "Latest wins",
            "What you finished lately",
            "Your FACODI toolbox",
        ]) {
            if (!bodyText.includes(marker)) {
                throw new Error(`portal ${sizeName}: missing copy marker ${marker}`);
            }
        }

        const overflow = await page.evaluate(() => ({
            scrollWidth: document.documentElement.scrollWidth,
            viewportWidth: window.innerWidth,
            overflow: document.documentElement.scrollWidth > window.innerWidth + 1,
        }));
        if (overflow.overflow) {
            throw new Error(
                `portal ${sizeName}: page-level horizontal overflow ${overflow.scrollWidth}px > ${overflow.viewportWidth}px`
            );
        }

        await page.screenshot({
            path: path.join(screenshotDir, `portal-home-${sizeName}.png`),
            fullPage: true,
        });
        console.log(`PASS portal-home ${sizeName} ${viewport.width}x${viewport.height}`);
        await context.close();
    }

    const reducedContext = await browser.newContext({
        viewport: viewports.mobile,
        reducedMotion: "reduce",
    });
    const reducedPage = await reducedContext.newPage();
    const reducedResponse = await reducedPage.goto(baseUrl + "/slides", {
        waitUntil: "domcontentloaded",
        timeout: 30000,
    });
    if (!reducedResponse || reducedResponse.status() >= 400) {
        throw new Error("reduced-motion course catalogue failed to load");
    }
    if ((await reducedPage.locator(".facodi-learning-catalogue-hero").count()) < 1) {
        throw new Error("reduced-motion mode hid the D1 course catalogue content");
    }
    await reducedContext.close();
} finally {
    await browser.close();
}
