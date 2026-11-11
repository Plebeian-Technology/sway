import { render, screen } from "@testing-library/react";
import { describe, it, expect } from "vitest";

import SwayLocaleFlag from "app/frontend/components/locales/SwayLocaleFlag";

// @lat: [[locale-flag-not-seal-design#Why SwayLocaleFlag is a flag, never a seal]]
describe("SwayLocaleFlag", () => {
    it("resolves the flag by locale name, the convention README documents", () => {
        render(<SwayLocaleFlag swayLocaleSlug="baltimore-maryland-united_states" />);

        expect(screen.getByRole("presentation", { hidden: true })).toHaveAttribute(
            "src",
            "/images/flags/baltimore-maryland-united_states.svg",
        );
    });

    it("carries no accessible name, so the jurisdiction is not announced twice", () => {
        render(<SwayLocaleFlag swayLocaleSlug="congress-congress-united_states" />);

        const flag = screen.getByRole("presentation", { hidden: true });
        expect(flag).toHaveAttribute("alt", "");
        expect(flag).toHaveAttribute("aria-hidden", "true");
    });

    it("degrades to no emblem when a locale has no flag yet", () => {
        render(<SwayLocaleFlag swayLocaleSlug="nowhere-nowhere-united_states" />);

        const flag = screen.getByRole("presentation", { hidden: true });
        flag.dispatchEvent(new Event("error", { bubbles: true }));

        expect(flag).not.toBeVisible();
    });

    // @lat: [[locale-flag-not-seal-design#Why the flag image is hidden with onLoad and onError instead of useEffect]]
    it("shows the emblem again once a locale that has a flag loads", () => {
        const { rerender } = render(<SwayLocaleFlag swayLocaleSlug="nowhere-nowhere-united_states" />);

        const flag = screen.getByRole("presentation", { hidden: true });
        flag.dispatchEvent(new Event("error", { bubbles: true }));
        expect(flag).not.toBeVisible();

        rerender(<SwayLocaleFlag swayLocaleSlug="baltimore-maryland-united_states" />);
        flag.dispatchEvent(new Event("load", { bubbles: true }));

        expect(flag).toBeVisible();
    });

    it("takes the caller's class so each theme sizes its own emblem", () => {
        render(<SwayLocaleFlag swayLocaleSlug="maryland-maryland-united_states" className="bal-locale__flag" />);

        expect(screen.getByRole("presentation", { hidden: true })).toHaveClass("bal-locale__flag");
    });
});
