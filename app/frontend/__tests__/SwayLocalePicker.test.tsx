import { cleanup, render, screen } from "@testing-library/react";
import { describe, it, expect, vi, afterEach } from "vitest";

import SwayLocalePicker from "app/frontend/components/locales/SwayLocalePicker";
import { NEO_SELECT_CLASS } from "app/frontend/components/ui/LocaleSelect";
import { THEMES } from "app/frontend/styles/themes";

const OPTIONS = [
    { label: "Baltimore, Maryland, United States", value: 1 },
    { label: "U.S. Congress", value: 3 },
];

const renderIn = (theme: string) => {
    cleanup();
    document.documentElement.dataset.theme = theme;
    render(<SwayLocalePicker id="locale" options={OPTIONS} value={1} onChange={vi.fn<(value: number) => void>()} />);
    return screen.getByRole("combobox");
};

afterEach(cleanup);

// @lat: [[theme-tokens#Theme tokens#Why native select chrome is defined once, globally]]
describe("SwayLocalePicker", () => {
    it("takes the active theme's select chrome", () => {
        expect(renderIn("ballot")).toHaveClass("ball-select");
    });

    it("falls back to the neo chrome for a theme that dresses no controls of its own", () => {
        expect(renderIn("sway")).toHaveClass(NEO_SELECT_CLASS.split(" ")[0]);
    });

    // @lat: [[theme-tokens#Theme tokens#Why the picker test names every theme's chrome]]
    const EXPECTED_CHROME: Record<string, string> = {
        sway: NEO_SELECT_CLASS,
        ballot: "ball-select",
        banner: "bnl-select",
        cornerstore: "csl-select",
        monochrome: "monochrome-select",
        "service-manual": "service-manual-select",
        "swiss-grid": "swiss-grid-select",
    };

    it("records a chrome decision for every registered theme", () => {
        expect(Object.keys(EXPECTED_CHROME).sort()).toEqual(THEMES.map((theme) => theme.id).sort());
    });

    it("resolves the recorded chrome for every registered theme", () => {
        for (const theme of THEMES) {
            const picker = renderIn(theme.id);
            expect(picker.className, `theme ${theme.id} resolved the wrong select chrome`).toBe(
                EXPECTED_CHROME[theme.id],
            );
        }
    });

    it("reports the chosen locale id as a number, not the raw option string", () => {
        const onChange = vi.fn<(value: number) => void>();
        document.documentElement.dataset.theme = "ballot";
        render(<SwayLocalePicker id="locale" options={OPTIONS} value={1} onChange={onChange} />);

        const picker = screen.getByRole("combobox") as HTMLSelectElement;
        picker.value = "3";
        picker.dispatchEvent(new Event("change", { bubbles: true }));

        expect(onChange).toHaveBeenCalledWith(3);
    });
});
