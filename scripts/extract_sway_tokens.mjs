#!/usr/bin/env node
// @lat: [[theme-tokens#Why the mobile app generates its palette from sway.css]]
import fs from "node:fs";
import path from "node:path";

const SOURCE = "app/frontend/styles/themes/sway.css";
const OUT = "mobile/src/theme/tokens.ts";
const OUT_CJS = "mobile/src/theme/tokens.js";

const TOKEN_KEYS = [
    "background",
    "foreground",
    "card",
    "card-foreground",
    "popover",
    "popover-foreground",
    "primary",
    "primary-foreground",
    "secondary",
    "secondary-foreground",
    "muted",
    "muted-foreground",
    "accent",
    "accent-foreground",
    "destructive",
    "border",
    "border-soft",
    "border-strong",
    "input",
    "ring",
    "success",
    "success-foreground",
    "warning",
    "warning-foreground",
    "info",
    "info-foreground",
    "surface-1",
    "surface-2",
    "surface-3",
    "vote-for",
    "vote-against",
    "muted-icon",
    "avatar-border",
    "chart-muted",
    "scrim",
];

function kebabToCamel(s) {
    return s.replace(/-([a-z0-9])/g, (_m, c) => c.toUpperCase());
}

function extractBlock(css, headerRegex) {
    const headerMatch = css.match(headerRegex);
    if (!headerMatch) {
        throw new Error(
            `extract_sway_tokens: could not locate block matching ${headerRegex} in ${SOURCE}`,
        );
    }
    const start = headerMatch.index + headerMatch[0].length;
    let depth = 1;
    let i = start;
    while (i < css.length && depth > 0) {
        if (css[i] === "{") depth++;
        else if (css[i] === "}") depth--;
        i++;
    }
    if (depth !== 0) {
        throw new Error(`extract_sway_tokens: unmatched braces after ${headerRegex}`);
    }
    return css.slice(start, i - 1);
}

function parseTokens(block) {
    const out = {};
    const lines = block.split("\n");
    for (const raw of lines) {
        const line = raw.trim();
        const m = line.match(/^--([a-z0-9-]+)\s*:\s*([^;]+);?$/i);
        if (!m) continue;
        const key = m[1];
        const value = m[2].trim();
        out[key] = value;
    }
    return out;
}

function pickColors(parsed) {
    const out = {};
    for (const k of TOKEN_KEYS) {
        if (parsed[k] === undefined) continue;
        out[kebabToCamel(k)] = parsed[k];
    }
    return out;
}

function emit(light, dark) {
    const header = "// @lat: [[theme-tokens#Why the mobile app generates its palette from sway.css]]";
    return (
        header +
        "\n" +
        "export const swayTokens = {\n" +
        `    light: ${JSON.stringify(light, null, 8).replace(/\n/g, "\n    ")},\n` +
        `    dark: ${JSON.stringify(dark, null, 8).replace(/\n/g, "\n    ")},\n` +
        "} as const;\n" +
        "\nexport type SwayColorScheme = keyof typeof swayTokens;\n"
    );
}

function main() {
    const css = fs.readFileSync(SOURCE, "utf8");

    const lightBlock = extractBlock(css, /\[data-theme="sway"\]\s*\{/);
    const darkBlock = extractBlock(css, /\[data-theme="sway"\]\.dark\s*\{/);

    const lightParsed = parseTokens(lightBlock);
    const darkParsed = parseTokens(darkBlock);

    const lightColors = pickColors(lightParsed);
    const darkColors = { ...lightColors, ...pickColors(darkParsed) };

    const missing = TOKEN_KEYS.filter((k) => lightParsed[k] === undefined);
    if (missing.length) {
        throw new Error(
            `extract_sway_tokens: missing required tokens in light block: ${missing.join(", ")}`,
        );
    }

    fs.mkdirSync(path.dirname(OUT), { recursive: true });
    fs.writeFileSync(OUT, emit(lightColors, darkColors));
    process.stdout.write(`wrote ${OUT}\n`);

    const cjsBody =
        "// @lat: [[theme-tokens#Why the mobile app generates its palette from sway.css]]\n" +
        "const swayTokens = " +
        JSON.stringify(
            { light: lightColors, dark: darkColors },
            null,
            4,
        ) +
        ";\n\nmodule.exports = { swayTokens };\n";
    fs.writeFileSync(OUT_CJS, cjsBody);
    process.stdout.write(`wrote ${OUT_CJS}\n`);
}

main();
