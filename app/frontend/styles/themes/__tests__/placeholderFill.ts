import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { THEMES_DIR } from "app/frontend/styles/themes/__tests__/themeFiles";

// @lat: [[navigation-placeholder-tracer#Where the placeholder fill's 1.2:1 floor comes from]]

/** The stylesheet that declares the placeholder fill, one level above the themes. */
export const APPLICATION_CSS = resolve(THEMES_DIR, "..", "application.css");

/** The body of the first rule whose opener matches, brace-balanced so nested keyframe stops survive. */
export const bodyOf = (css: string, opener: RegExp, label: string): string => {
    const match = opener.exec(css);
    if (!match) throw new Error(`application.css no longer contains ${label}`);

    const start = css.indexOf("{", match.index);
    let depth = 0;
    for (let i = start; i < css.length; i += 1) {
        if (css[i] === "{") depth += 1;
        if (css[i] === "}") {
            depth -= 1;
            if (depth === 0) return css.slice(start + 1, i);
        }
    }
    throw new Error(`application.css leaves ${label} unclosed`);
};

const fillPercentagesIn = (body: string): number[] =>
    [...body.matchAll(/color-mix\(\s*in srgb,\s*var\(--muted-foreground\)\s*(\d+)%/g)].map((m) => Number(m[1]));

const oneFillPercentage = (body: string, label: string): number => {
    const found = fillPercentagesIn(body);
    if (found.length !== 1) {
        throw new Error(
            `${label} declares ${found.length} --muted-foreground mixes in application.css, expected exactly 1`,
        );
    }
    return found[0];
};

/** Every distinct placeholder fill the app paints, keyed by the label a failure should name. */
export const placeholderFillPercentages = (): Record<string, number> => {
    const css = readFileSync(APPLICATION_CSS, "utf8");

    const resting = oneFillPercentage(
        bodyOf(css, /@utility\s+placeholder-block\s*\{/, "@utility placeholder-block"),
        "@utility placeholder-block",
    );

    const pulse = bodyOf(css, /@keyframes\s+placeholder-pulse\s*\{/, "@keyframes placeholder-pulse");
    const stops = new Map<number, number>();
    for (const stop of pulse.matchAll(/(\d+)%\s*\{([^}]*)\}/g)) {
        stops.set(Number(stop[1]), oneFillPercentage(stop[2], `@keyframes placeholder-pulse ${stop[1]}%`));
    }

    const low = stops.get(0);
    const high = stops.get(100);
    if (low === undefined || high === undefined) {
        throw new Error("@keyframes placeholder-pulse no longer declares both a 0% and a 100% stop");
    }

    // The 0% stop was raised to meet the resting fill, so while they agree they are one
    // measurement under one label rather than the same mix measured twice per theme.
    return low === resting
        ? { "resting / pulse low (0%)": low, "pulse high (100%)": high }
        : { resting: resting, "pulse low (0%)": low, "pulse high (100%)": high };
};
