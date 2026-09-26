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
const screenshotDir = required("FACODI_D2_BROWSER_SCREENSHOT_DIR");
const aboutRoute = required("FACODI_D2_ABOUT_ROUTE");
const contributionRoute = required("FACODI_D2_CONTRIBUTION_ROUTE");
const policyRoute = required("FACODI_D2_POLICY_ROUTE");
const richPostRoute = required("FACODI_D2_RICH_POST_ROUTE");
const sparsePostRoute = required("FACODI_D2_SPARSE_POST_ROUTE");

await fs.mkdir(screenshotDir, { recursive: true });

const viewports = {
    desktop: { width: 1440, height: 1200 },
    tablet: { width: 1024, height: 1366 },
    mobile: { width: 390, height: 844 },
    narrow: { width: 320, height: 700 },
};

const cases = [
    {
        name: "about",
        route: aboutRoute,
        sizes: ["desktop", "tablet", "mobile", "narrow"],
        selectors: [".facodi-project-story", ".facodi-principles-ledger", ".facodi-process-timeline"],
    },
    {
        name: "contribution",
        route: contributionRoute,
        sizes: ["desktop", "mobile", "narrow"],
        selectors: [".facodi-contribution-board", ".facodi-process-timeline"],
    },
    {
        name: "blog-index",
        route: "/blog",
        sizes: ["desktop", "mobile", "narrow"],
        selectors: [".facodi-blog-index", ".facodi-bulletin-hero", ".facodi-bulletin-card"],
    },
    {
        name: "blog-rich",
        route: richPostRoute,
        sizes: ["desktop", "mobile"],
        selectors: [".facodi-blog-article", ".facodi-blog-prose"],
    },
    {
        name: "blog-sparse",
        route: sparsePostRoute,
        sizes: ["mobile"],
        selectors: [".facodi-blog-article", ".facodi-blog-prose"],
    },
    {
        name: "contact",
        route: "/contactus",
        sizes: ["desktop", "mobile", "narrow"],
        selectors: [".facodi-contact-page", ".facodi-contact-form-sheet", ".facodi-contact-context"],
        contact: true,
    },
    {
        name: "policy",
        route: policyRoute,
        sizes: ["desktop", "mobile", "narrow"],
        selectors: [".facodi-policy-document"],
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
                throw new Error(`${testCase.name} ${sizeName}: HTTP ${response ? response.status() : "no response"}`);
            }
            await page.waitForLoadState("networkidle", { timeout: 5000 }).catch(() => {});

            for (const selector of testCase.selectors) {
                if ((await page.locator(selector).count()) < 1) {
                    throw new Error(`${testCase.name} ${sizeName}: missing selector ${selector}`);
                }
            }

            const footer = page.locator("footer#bottom");
            if ((await footer.count()) !== 1) {
                throw new Error(`${testCase.name} ${sizeName}: expected exactly one Odoo footer shell`);
            }
            const footerBackground = await footer.evaluate(
                (element) => getComputedStyle(element).backgroundColor
            );
            if (footerBackground !== "rgb(11, 19, 37)") {
                throw new Error(
                    `${testCase.name} ${sizeName}: footer background is ${footerBackground}, expected rgb(11, 19, 37)`
                );
            }
            if ((await page.locator(".o_brand_promotion").count()) !== 0) {
                throw new Error(`${testCase.name} ${sizeName}: Odoo brand promotion is still rendered`);
            }
            if ((await page.locator('img[src*="odoo_logo_tiny.png"]').count()) !== 0) {
                throw new Error(`${testCase.name} ${sizeName}: Odoo footer logo is still rendered`);
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

            if (testCase.contact) {
                const forms = page.locator("form#contactus_form");
                if ((await forms.count()) !== 1) {
                    throw new Error(`${testCase.name} ${sizeName}: expected exactly one native Contact form`);
                }
                const action = await forms.first().getAttribute("action");
                if (action !== "/website/form/") {
                    throw new Error(`${testCase.name} ${sizeName}: native Contact action changed to ${action}`);
                }
                for (const name of ["name", "phone", "email_from", "company", "subject", "description"]) {
                    if ((await forms.locator(`[name="${name}"]`).count()) < 1) {
                        throw new Error(`${testCase.name} ${sizeName}: missing native Contact field ${name}`);
                    }
                }
                if ((await forms.locator(".s_website_form_send").count()) !== 1) {
                    throw new Error(`${testCase.name} ${sizeName}: native Contact submit control missing`);
                }
            }

            if (testCase.name === "blog-rich") {
                const text = await page.locator("#o_wblog_post_top").innerText();
                if (!text.includes("A real D2 deployment subtitle")) {
                    throw new Error("rich Blog article lost its native subtitle");
                }
            }
            if (testCase.name === "blog-sparse") {
                const subtitles = page.locator("#o_wblog_post_top .o_wblog_post_subtitle");
                if ((await subtitles.count()) !== 0) {
                    throw new Error("sparse Blog article fabricated a subtitle");
                }
            }

            const screenshotPath = path.join(screenshotDir, `${testCase.name}-${sizeName}.png`);
            await page.screenshot({ path: screenshotPath, fullPage: true });
            console.log(`PASS D2 ${testCase.name} ${sizeName} ${viewport.width}x${viewport.height}`);
            await context.close();
        }
    }

    const reducedContext = await browser.newContext({
        viewport: viewports.mobile,
        reducedMotion: "reduce",
    });
    const reducedPage = await reducedContext.newPage();
    const response = await reducedPage.goto(baseUrl + contributionRoute, {
        waitUntil: "domcontentloaded",
        timeout: 30000,
    });
    if (!response || response.status() >= 400) {
        throw new Error("D2 reduced-motion contribution page failed to load");
    }
    if ((await reducedPage.locator(".facodi-contribution-board").count()) < 1) {
        throw new Error("D2 reduced-motion mode hid editorial content");
    }
    await reducedContext.close();
} finally {
    await browser.close();
}
