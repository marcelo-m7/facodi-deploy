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
const videoRoute = required("FACODI_BROWSER_VIDEO_ROUTE");

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

    // Exercise the same native fullscreen video surface used by production
    // lessons. The FACODI shell may restyle it, but the Odoo-generated YouTube
    // iframe must remain mounted, visible and large enough to be usable.
    {
        const context = await browser.newContext({ viewport: viewports.desktop });
        const page = await openPage(
            context,
            videoRoute + "?fullscreen=1",
            "fullscreen native video"
        );
        await page.locator(".facodi-study-player").first().waitFor({
            state: "visible",
            timeout: 10000,
        });
        const iframe = page.locator(
            '.facodi-study-player__content iframe[src*="youtube-nocookie.com/embed/"]'
        ).first();
        await iframe.waitFor({ state: "visible", timeout: 10000 });
        const box = await iframe.boundingBox();
        if (!box || box.width < 640 || box.height < 360) {
            throw new Error(
                `fullscreen native video: unusable iframe bounds ${JSON.stringify(box)}`
            );
        }
        const category = await page.locator("body").evaluate(() => {
            const player = document.querySelector(".facodi-study-player__content");
            return {
                playerWidth: player?.getBoundingClientRect().width || 0,
                playerHeight: player?.getBoundingClientRect().height || 0,
            };
        });
        if (category.playerWidth < 640 || category.playerHeight < 360) {
            throw new Error(
                `fullscreen native video: content surface collapsed ${JSON.stringify(category)}`
            );
        }
        await assertViewport(page, "fullscreen native video");
        await page.screenshot({
            path: path.join(screenshotDir, "fullscreen-native-video-desktop.png"),
            fullPage: true,
        });
        console.log("PASS fullscreen native video desktop");
        await context.close();
    }

    // Follow a real contextual CTA from a public curricular-unit gap into the
    // unified intake. This proves the browser experience carries the learning
    // context rather than merely accepting equivalent query parameters.
    {
        const context = await browser.newContext({ viewport: viewports.mobile });
        const page = await openPage(context, unitRoute, "contextual resource CTA");
        const contribution = page.locator(
            'a[href*="/submissions/new?"][href*="type=resource"][href*="source=unit_resource_cta"]'
        ).first();
        await contribution.waitFor({ state: "visible", timeout: 5000 });
        await contribution.click();
        await page.waitForURL(/\/submissions\/new\?/, { timeout: 30000 });

        for (const selector of [
            '[data-facodi-submission-form="1"]',
            '[data-facodi-contribution-brief="1"]',
            'input[name="submission_type"][value="resource"]',
            'input[name="source_cta"][value="unit_resource_cta"]',
            'input[name="source_section"][value="resources"]',
            'select[name="resource_type"]',
            'textarea[name="context"]',
        ]) {
            await page.locator(selector).first().waitFor({ state: "attached", timeout: 5000 });
        }

        const carriedUnitId = await page.locator('input[name="curriculum_unit_id"]').inputValue();
        if (!carriedUnitId) {
            throw new Error("contextual resource CTA: curricular-unit id was not carried into the intake");
        }
        const briefText = await page.locator('[data-facodi-contribution-brief="1"]').innerText();
        if (!briefText.includes("Curricular unit")) {
            throw new Error("contextual resource CTA: contribution brief lost curricular-unit context");
        }
        await assertViewport(page, "contextual resource intake mobile");
        await page.screenshot({
            path: path.join(screenshotDir, "contextual-resource-intake-mobile.png"),
            fullPage: true,
        });
        console.log("PASS contextual resource intake mobile 390x844");
        await context.close();
    }

    // The canonical contact route also accepts explicit CTA provenance. The
    // visible copy must stay human-readable while the hidden source remains
    // available to editorial routing.
    {
        const context = await browser.newContext({ viewport: viewports.mobile });
        const route = "/contact?source=faq_contact_cta&section=faq&topic=collaboration";
        const page = await openPage(context, route, "contextual FAQ contact");

        for (const selector of [
            '[data-facodi-submission-form="1"]',
            '[data-facodi-contribution-brief="1"]',
            'input[name="submission_type"][value="contact"]',
            'input[name="source_cta"][value="faq_contact_cta"]',
            'input[name="source_section"][value="faq"]',
            'select[name="contact_topic"]',
        ]) {
            await page.locator(selector).first().waitFor({ state: "attached", timeout: 5000 });
        }

        const topic = await page.locator('select[name="contact_topic"]').inputValue();
        if (topic !== "collaboration") {
            throw new Error(`contextual FAQ contact: expected collaboration topic, got ${topic}`);
        }
        const bodyText = await page.locator("body").innerText();
        if (!bodyText.includes("FAQ contact")) {
            throw new Error("contextual FAQ contact: human-readable CTA origin is missing");
        }
        if (bodyText.includes("faq_contact_cta")) {
            throw new Error("contextual FAQ contact: technical CTA slug leaked into visible copy");
        }
        await assertViewport(page, "contextual FAQ contact mobile");
        await page.screenshot({
            path: path.join(screenshotDir, "contextual-faq-contact-mobile.png"),
            fullPage: true,
        });
        console.log("PASS contextual FAQ contact mobile 390x844");
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

    // The backend keeps MuK as its theme while Monodoo contributes only the
    // neutral application Home/launcher.
    {
        const context = await browser.newContext({ viewport: viewports.desktop });
        const page = await context.newPage();
        await page.goto(baseUrl + "/web/login?redirect=/odoo", {
            waitUntil: "domcontentloaded",
            timeout: 30000,
        });
        await page.locator('input[name="login"]').fill("admin");
        await page.locator('input[name="password"]').fill("facodi-ci-admin");
        await page.locator('form.oe_login_form button[type="submit"]').click();
        await page.locator(".o_monodoo_home").first().waitFor({
            state: "visible",
            timeout: 30000,
        });
        await page.locator(".o_monodoo_all_apps").first().waitFor({
            state: "visible",
            timeout: 10000,
        });
        await assertViewport(page, "Monodoo Home with MuK");
        await page.screenshot({
            path: path.join(screenshotDir, "backend-monodoo-home-muk-desktop.png"),
            fullPage: true,
        });
        console.log("PASS backend Monodoo Home with muk_web_theme");
        await context.close();
    }
} finally {
    await browser.close();
}
