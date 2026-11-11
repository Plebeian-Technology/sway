import { readdirSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

// @lat: [[theme-test-suite-silent-failure-guards#Shared file discovery: __dirname vs process.cwd() drift]]
export const THEMES_DIR = resolve(__dirname, "..");

/** Every theme's filename, sorted. `["ballot.css", "banner.css", …]` */
export const THEME_FILES = readdirSync(THEMES_DIR)
    .filter((f) => f.endsWith(".css"))
    .sort();

/** The same list as theme names, sorted. `["ballot", "banner", …]` */
export const THEME_NAMES = THEME_FILES.map((f) => f.replace(/\.css$/, ""));

/** The CSS text of one theme, looked up by name. */
export const themeCss = (theme: string): string => readFileSync(resolve(THEMES_DIR, `${theme}.css`), "utf8");
