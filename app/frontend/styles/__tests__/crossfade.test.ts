import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { APPLICATION_CSS, bodyOf } from "app/frontend/styles/themes/__tests__/placeholderFill";

// @lat: [[system-shape#What a reader sees during the round trip#Why the crossfade is cancelled rather than shortened under reduced motion]]

const CROSSFADE_SELECTOR = "::view-transition-old(root), ::view-transition-new(root)";
const CROSSFADE_OPENER = /::view-transition-old\(root\),\s*::view-transition-new\(root\)\s*\{/;
const REDUCED_MOTION_LABEL = "@media (prefers-reduced-motion: reduce)";
const REDUCED_MOTION_OPENER = /@media\s*\(prefers-reduced-motion:\s*reduce\)\s*\{/;

/** Every reduced-motion block in the stylesheet; application.css declares more than one. */
const reducedMotionBodies = (css: string): string[] => {
    const bodies: string[] = [];
    let rest = css;
    while (REDUCED_MOTION_OPENER.test(rest)) {
        const body = bodyOf(rest, REDUCED_MOTION_OPENER, REDUCED_MOTION_LABEL);
        bodies.push(body);
        rest = rest.slice(rest.indexOf(body) + body.length);
    }
    return bodies;
};

describe("root view-transition crossfade", () => {
    const css = readFileSync(APPLICATION_CSS, "utf8");

    it("times the crossfade off --dur-2 with a literal fallback", () => {
        const body = bodyOf(css, CROSSFADE_OPENER, CROSSFADE_SELECTOR);

        expect(
            /animation-duration:\s*var\(--dur-2,\s*\d+m?s\)/.test(body),
            `${CROSSFADE_SELECTOR} no longer times its animation off var(--dur-2, <fallback>)`,
        ).toBe(true);
    });

    it("cancels the crossfade animation under prefers-reduced-motion", () => {
        const cancelled = reducedMotionBodies(css).some(
            (media) =>
                CROSSFADE_OPENER.test(media) &&
                /animation:\s*none\s*;/.test(bodyOf(media, CROSSFADE_OPENER, CROSSFADE_SELECTOR)),
        );

        expect(cancelled, `no ${REDUCED_MOTION_LABEL} block sets animation: none on ${CROSSFADE_SELECTOR}`).toBe(true);
    });
});
