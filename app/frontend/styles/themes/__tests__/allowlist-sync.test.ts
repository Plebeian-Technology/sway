import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, it, expect } from "vitest";
import { THEMES } from "app/frontend/styles/themes/index";

// @lat: [[theme-test-suite-silent-failure-guards#Theme-id allowlist: two hand-maintained lists with nothing generating one from the other]]
const ROOT = resolve(__dirname, "../../../../../");
const themeHelperPath = resolve(ROOT, "app/helpers/theme_helper.rb");

// Extract the %w[...] members of VALID_THEME_IDS from the Ruby source.
function rubyValidThemeIds(): string[] {
    const ruby = readFileSync(themeHelperPath, "utf8");
    const match = ruby.match(/VALID_THEME_IDS\s*=\s*%w\[([^\]]*)\]/);
    if (!match) {
        throw new Error(
            `Could not locate VALID_THEME_IDS = %w[...] in ${themeHelperPath}. ` +
                "If the Ruby constant was renamed or reformatted, update this test's regex.",
        );
    }
    return match[1].trim().split(/\s+/).filter(Boolean);
}

describe("theme-id allowlist cross-language sync (WR-04)", () => {
    it("Ruby ThemeHelper::VALID_THEME_IDS equals the TS THEMES manifest ids", () => {
        const rubyIds = [...rubyValidThemeIds()].sort();
        const tsIds = THEMES.map((t) => t.id).sort();

        // Spell out the difference, so a failure names the ids that do not match.
        const missingInTs = rubyIds.filter((id) => !tsIds.includes(id as (typeof tsIds)[number]));
        const missingInRuby = tsIds.filter((id) => !rubyIds.includes(id));
        if (missingInTs.length > 0 || missingInRuby.length > 0) {
            const lines: string[] = [];
            if (missingInTs.length > 0) {
                lines.push(`Ruby allows but TS THEMES is missing: ${missingInTs.join(", ")}`);
            }
            if (missingInRuby.length > 0) {
                lines.push(`TS THEMES allows but Ruby VALID_THEME_IDS is missing: ${missingInRuby.join(", ")}`);
            }
            throw new Error(lines.join("\n"));
        }

        expect(tsIds).toEqual(rubyIds);
    });
});
