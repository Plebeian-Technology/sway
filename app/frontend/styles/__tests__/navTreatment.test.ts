import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { APPLICATION_CSS, bodyOf } from "app/frontend/styles/themes/__tests__/placeholderFill";

// @lat: [[system-shape#What a reader sees during the round trip#Why the outgoing page is not painted under the placeholder]]

const opacityIn = (body: string, label: string): string => {
    const match = /opacity:\s*([^;]+);/.exec(body);
    if (!match) throw new Error(`${label} no longer declares an opacity`);
    return match[1].trim();
};

describe("navigation paint treatments", () => {
    const css = readFileSync(APPLICATION_CSS, "utf8");

    it("paints nothing of the outgoing page while a placeholder holds the cell", () => {
        const body = bodyOf(css, /@utility\s+nav-replaced\s*\{/, "@utility nav-replaced");

        expect(opacityIn(body, "@utility nav-replaced")).toBe("0");
    });

    it("keeps the outgoing page legible under a dim that draws no placeholder", () => {
        const body = bodyOf(css, /@utility\s+nav-leaving\s*\{/, "@utility nav-leaving");
        const opacity = opacityIn(body, "@utility nav-leaving");
        const fallback = /var\(--nav-leaving-opacity,\s*([\d.]+)\)/.exec(opacity);

        expect(fallback, `@utility nav-leaving no longer reads var(--nav-leaving-opacity, <fallback>)`).not.toBeNull();
        expect(Number(fallback?.[1])).toBeGreaterThan(0);
    });

    it("rounds the placeholder off the theme's own radius rather than a fixed length", () => {
        const body = bodyOf(css, /@utility\s+placeholder-block\s*\{/, "@utility placeholder-block");
        const radius = /border-radius:\s*([^;]+);/.exec(body);

        expect(radius, "@utility placeholder-block no longer declares a border-radius").not.toBeNull();
        expect(
            /calc\(\s*var\(--radius-md\)\s*\*\s*[\d.]+\s*\)/.test(radius?.[1] ?? ""),
            "@utility placeholder-block no longer scales var(--radius-md); a fixed length would round the square themes",
        ).toBe(true);
    });

    it("fades both treatments over --dur-1 with a literal fallback", () => {
        for (const utility of ["nav-replaced", "nav-leaving"]) {
            const body = bodyOf(css, new RegExp(`@utility\\s+${utility}\\s*\\{`), `@utility ${utility}`);

            expect(
                /transition:\s*opacity\s+var\(--dur-1,\s*\d+m?s\)/.test(body),
                `@utility ${utility} no longer transitions opacity over var(--dur-1, <fallback>)`,
            ).toBe(true);
        }
    });
});
