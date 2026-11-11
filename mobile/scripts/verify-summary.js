#!/usr/bin/env node
// Schema-validates mobile/docs/parity-evidence/manifest.json against the locked
// 38-UI-SPEC schema. Exit 0 = valid; non-zero = at least one violation.
//
// Locked rules:
//   - threshold_pct === 5.0
//   - pixelmatch_version === "7.2.0"
//   - every per-screen entry has all 11 keys
//   - pass === false  ⇒  waiver_reason is a non-empty string (T-38-VAL contract)
//   - notes must not contain phone-number-like patterns (anti-PII guard)

import { readFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const MANIFEST = join(__dirname, "..", "docs", "parity-evidence", "manifest.json");

const required = [
    "generated",
    "ios_device",
    "ios_viewport_logical",
    "ios_viewport_physical",
    "android_device",
    "web_viewport",
    "comparison_canvas",
    "threshold_pct",
    "pixelmatch_version",
    "screens",
];

const screenRequired = [
    "id",
    "parity",
    "web_url",
    "web_png",
    "mobile_png",
    "diff_png",
    "ios_diff_pct",
    "android_diff_pct",
    "pass",
    "waiver_reason",
    "notes",
];

let manifest;
try {
    manifest = JSON.parse(readFileSync(MANIFEST, "utf8"));
} catch (e) {
    console.error(`[verify-summary] cannot read ${MANIFEST}: ${e.message}`);
    process.exit(1);
}

let errors = 0;

for (const k of required) {
    if (!(k in manifest)) {
        console.error(`MISSING manifest.${k}`);
        errors++;
    }
}

if (manifest.threshold_pct !== 5.0) {
    console.error(`threshold_pct must be 5.0 (got ${manifest.threshold_pct})`);
    errors++;
}
if (manifest.pixelmatch_version !== "7.2.0") {
    console.error(
        `pixelmatch_version must be 7.2.0 (got ${manifest.pixelmatch_version})`,
    );
    errors++;
}

if (Array.isArray(manifest.screens)) {
    for (const s of manifest.screens) {
        for (const k of screenRequired) {
            if (!(k in s)) {
                console.error(`MISSING screens[${s.id || "?"}].${k}`);
                errors++;
            }
        }
        // Locked rule from 38-UI-SPEC §Threshold contract: pass === false ⇒ waiver_reason set
        if (
            s.pass === false &&
            !(typeof s.waiver_reason === "string" && s.waiver_reason.trim())
        ) {
            console.error(
                `screen "${s.id}" has pass=false but no waiver_reason`,
            );
            errors++;
        }
        // Anti-PII guard: notes must be plain strings, no phone-number-like patterns.
        // Pattern matches NNN-NNN-NNNN or NNN NNN NNNN (10-digit US-style).
        if (
            typeof s.notes === "string" &&
            /\b\d{3}[- ]\d{3}[- ]\d{4}\b/.test(s.notes)
        ) {
            console.error(
                `screen "${s.id}" notes contains a phone-number-like pattern (PII)`,
            );
            errors++;
        }
    }
} else {
    console.error("manifest.screens must be an array");
    errors++;
}

if (errors === 0) {
    console.log(`manifest.json valid: ${manifest.screens.length} screens`);
}
process.exit(errors === 0 ? 0 : 1);
