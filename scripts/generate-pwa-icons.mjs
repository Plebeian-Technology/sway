// Wrapper around @vite-pwa/assets-generator. Regenerate maskable icons
// after any source logo change. Run: node scripts/generate-pwa-icons.mjs
import { execSync } from "node:child_process";
import { renameSync, existsSync, readdirSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(process.cwd());
const source = "public/images/logo512.png";
if (!existsSync(resolve(root, source))) {
    console.error(`missing source icon: ${resolve(root, source)}`);
    process.exit(1);
}

// --preset minimal generates: pwa-64x64.png, pwa-192x192.png, pwa-512x512.png,
//   maskable-icon-512x512.png, apple-touch-icon-180x180.png, favicon.ico
// --root . means image paths are relative to cwd
execSync(`./node_modules/.bin/pwa-assets-generator --preset minimal --root . ${source}`, {
    stdio: "inherit",
    cwd: root,
});

// Log what was generated so we can verify outputs
const generated = readdirSync(resolve(root, "public/images")).filter((f) => f.match(/^(pwa|maskable)/));
console.log("Generated files:", generated);

const renames = [
    ["public/images/maskable-icon-512x512.png", "public/images/logo512-maskable.png"],
    ["public/images/pwa-192x192.png", "public/images/logo192-maskable.png"],
];
for (const [from, to] of renames) {
    const src = resolve(root, from);
    const dst = resolve(root, to);
    if (existsSync(src)) {
        renameSync(src, dst);
        console.log(`renamed ${from} -> ${to}`);
    } else {
        console.warn(`source not found for rename: ${from}`);
    }
}
