import { chromium } from "playwright-core";

const executablePath = process.env.FACODI_BROWSER_CHROME_BIN;
if (!executablePath) throw new Error("FACODI_BROWSER_CHROME_BIN is required");

const baseUrl = "https://facodi.com";
const routes = [
    "/",
    "/pt/",
    "/slides",
    "/roadmaps",
    "/unidades-curriculares",
    "/sobre",
    "/contribuir",
    "/blog",
    "/contactus",
];

const browser = await chromium.launch({
    executablePath,
    headless: true,
    args: ["--no-sandbox", "--disable-dev-shm-usage"],
});

const failures = [];
try {
    for (const route of routes) {
        const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
        const page = await context.newPage();
        const errors = [];
        page.on("pageerror", (error) => {
            errors.push(error.stack || error.message || String(error));
        });
        page.on("console", (msg) => {
            if (msg.type() === "error") {
                const text = msg.text();
                if (/Cannot set properties of null|UncaughtPromiseError|TypeError/.test(text)) {
                    errors.push(`console: ${text}`);
                }
            }
        });

        const response = await page.goto(baseUrl + route, {
            waitUntil: "domcontentloaded",
            timeout: 30000,
        });
        await page.waitForTimeout(4000);
        await page.waitForLoadState("networkidle", { timeout: 5000 }).catch(() => {});

        const status = response?.status() ?? 0;
        const finalUrl = page.url();
        console.log(`CHECK ${route} -> ${status} ${finalUrl}`);
        if (errors.length) {
            console.log(`PAGEERROR ${route}\n${errors.join("\n---\n")}`);
            failures.push({ route, status, finalUrl, errors });
        }
        await context.close();
    }
} finally {
    await browser.close();
}

if (failures.length) {
    console.error(JSON.stringify(failures, null, 2));
    process.exit(1);
}

console.log("PASS: no production page errors detected on representative public routes");
