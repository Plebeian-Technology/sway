// Playwright authenticated session bootstrap.
//
// Launches a headed Chromium so the operator can complete the WebAuthn
// passkey ceremony (and SMS fallback if needed) against the local dev
// server, then serializes the resulting browser context to
// mobile/scripts/.auth/storageState.json for reuse by authenticated screen
// captures.
//
// Reuses the pnpm-store-cached Playwright install at @playwright+mcp@0.0.70 —
// no new dependency added.
//
// SECURITY: this script MUST NOT log cookie values, MUST NOT
// stringify or echo the storageState contents, and writes ONLY to the
// gitignored mobile/scripts/.auth/storageState.json path.

import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { mkdirSync, existsSync } from "fs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..", "..");

const PLAYWRIGHT_PATH = join(
    ROOT,
    "node_modules/.pnpm/@playwright+mcp@0.0.70/node_modules/playwright/index.js",
);

const AUTH_DIR = join(__dirname, ".auth");
const STATE_PATH = join(AUTH_DIR, "storageState.json");
const SIGN_IN_URL = process.env.PARITY_SIGN_IN_URL || "https://localhost:3333/sign-in";
const POST_LOGIN_TIMEOUT_MS = 5 * 60 * 1000; // 5 min for human passkey ceremony

if (!existsSync(AUTH_DIR)) mkdirSync(AUTH_DIR, { recursive: true });

const pw = await import(PLAYWRIGHT_PATH);
const chromium = (pw.default || pw).chromium;

const browser = await chromium.launch({ headless: false });
const context = await browser.newContext({ ignoreHTTPSErrors: true });
const page = await context.newPage();

console.log(`[parity-auth] Opening ${SIGN_IN_URL} — complete the passkey/SMS flow in the headed browser.`);
await page.goto(SIGN_IN_URL, { waitUntil: "domcontentloaded" });

// Wait until the URL no longer matches /sign-in (i.e. user is authenticated and redirected).
await page.waitForURL((url) => !url.pathname.startsWith("/sign-in"), { timeout: POST_LOGIN_TIMEOUT_MS });

await context.storageState({ path: STATE_PATH });
console.log(`[parity-auth] storageState written to ${STATE_PATH}`);

await browser.close();
