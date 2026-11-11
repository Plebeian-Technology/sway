// @lat: [[sway-logo-theme-immunity-test#Why SwayLogo.test.tsx guards against theming]]

import { cleanup, render } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";

import SwayLogo from "app/frontend/components/SwayLogo";

afterEach(cleanup);

describe("SwayLogo — brand-exempt from theming", () => {
    it("renders the fixed brand PNG as a raster <img>", () => {
        const { getByAltText } = render(<SwayLogo />);
        const logo = getByAltText("Sway");

        // CSS cannot recolor a picture file. Keeping the logo as an <img> of
        // this PNG is exactly what keeps the theme's hands off it.
        expect(logo.tagName).toBe("IMG");
        expect(logo.getAttribute("src")).toBe("/images/sway-us-light.png");
    });

    it("contributes no theme-driven styling of its own", () => {
        const { getByAltText } = render(<SwayLogo />);
        const logo = getByAltText("Sway");

        // SwayLogo passes along only the className the caller gives it and adds
        // none of its own, so it can never pick up a bg-, text-, border-, or
        // rounded- class from the theme.
        expect(logo.className).toBe("");
    });
});
