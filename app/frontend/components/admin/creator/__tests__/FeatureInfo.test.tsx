// A popover rather than a tooltip: Radix never opens a tooltip on a touch device, and these
// notes have to reach an operator working the Bill Creator on a phone.

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it } from "vitest";

import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import { FEATURE_NOTES, type TFeatureNoteKey } from "app/frontend/components/admin/creator/featureNotes";

const KEY: TFeatureNoteKey = "summary.publicSummary";
const TRIGGER = `feature-info-${KEY}`;
const CONTENT = `feature-info-content-${KEY}`;

afterEach(() => {
    cleanup();
});

describe("FeatureInfo", () => {
    it("shows nothing until the trigger is used", () => {
        render(<FeatureInfo note={KEY} />);

        expect(screen.getByTestId(TRIGGER)).toBeTruthy();
        expect(screen.queryByTestId(CONTENT)).toBeNull();
    });

    it("reveals the sentence when the trigger is clicked", async () => {
        render(<FeatureInfo note={KEY} />);

        await userEvent.click(screen.getByTestId(TRIGGER));

        expect(screen.getByTestId(CONTENT)).toBeTruthy();
    });

    it("hides the sentence when the trigger is clicked again", async () => {
        render(<FeatureInfo note={KEY} />);

        await userEvent.click(screen.getByTestId(TRIGGER));
        await userEvent.click(screen.getByTestId(TRIGGER));

        expect(screen.queryByTestId(CONTENT)).toBeNull();
    });

    it("hides the sentence on Escape", async () => {
        render(<FeatureInfo note={KEY} />);

        await userEvent.click(screen.getByTestId(TRIGGER));
        await userEvent.keyboard("{Escape}");

        expect(screen.queryByTestId(CONTENT)).toBeNull();
    });

    it("opens for a finger, which never hovers", () => {
        render(<FeatureInfo note={KEY} />);

        fireEvent.pointerOver(screen.getByTestId(TRIGGER), { pointerType: "touch" });
        expect(screen.queryByTestId(CONTENT)).toBeNull();

        fireEvent.click(screen.getByTestId(TRIGGER));
        expect(screen.getByTestId(CONTENT)).toBeTruthy();
    });

    it("opens on a mouse hover without taking the focus", () => {
        render(<FeatureInfo note={KEY} />);

        fireEvent.pointerOver(screen.getByTestId(TRIGGER), { pointerType: "mouse" });

        const content = screen.getByTestId(CONTENT);
        expect(content).toBeTruthy();
        expect(document.activeElement).not.toBe(content);
    });

    it("names the feature in the trigger's accessible name", () => {
        render(<FeatureInfo note={KEY} />);

        expect(screen.getByRole("button", { name: "Why this exists: the public summary box" })).toBeTruthy();
    });

    it("renders the registry's text for the key, character for character", async () => {
        render(<FeatureInfo note="summary.testimonyCoverage" />);

        await userEvent.click(screen.getByTestId("feature-info-summary.testimonyCoverage"));

        expect(screen.getByTestId("feature-info-content-summary.testimonyCoverage").textContent).toBe(
            FEATURE_NOTES["summary.testimonyCoverage"].note,
        );
    });

    it("renders the monthly sentence for schedule.calendar after opening its popover", async () => {
        render(<FeatureInfo note="schedule.calendar" />);

        await userEvent.click(screen.getByTestId("feature-info-schedule.calendar"));

        expect(screen.getByTestId("feature-info-content-schedule.calendar").textContent).toBe(
            "Only one bill can be the Bill of the Month on a given day, so this shows which days are already taken.",
        );
    });

    it("renders the monthly sentence for schedule.scheduleBill after opening its popover", async () => {
        render(<FeatureInfo note="schedule.scheduleBill" />);

        await userEvent.click(screen.getByTestId("feature-info-schedule.scheduleBill"));

        expect(screen.getByTestId("feature-info-content-schedule.scheduleBill").textContent).toBe(
            "This books the bill as the Bill of the Month that readers see on that day.",
        );
    });

    it("is a plain button that never submits a surrounding form", () => {
        render(<FeatureInfo note={KEY} />);

        expect(screen.getByTestId(TRIGGER).getAttribute("type")).toBe("button");
    });

    it("keeps a 44px pressable area on touch and shrinks it at sm and up", () => {
        render(<FeatureInfo note={KEY} />);

        // 16px glyph plus 14px of padding above and below is the 44px touch floor. The
        // padding that buys it is vertical only: a negative horizontal margin would lay
        // the hit area over the heading beside it and swallow the drag that selects it.
        const className = screen.getByTestId(TRIGGER).className;
        expect(className).toContain("py-3.5");
        expect(className).toContain("-my-3.5");
        expect(className).toContain("sm:py-2");
        expect(className).toContain("sm:-my-2");
        expect(className).not.toMatch(/(^|\s)-mx?-/);
    });

    it("never applies select-none (the operator copies these sentences out)", async () => {
        const { container } = render(<FeatureInfo note={KEY} />);

        await userEvent.click(screen.getByTestId(TRIGGER));

        expect(container.innerHTML).not.toContain("select-none");
        expect(document.body.innerHTML).not.toContain("select-none");
    });

    it("takes extra classes from the call site", () => {
        render(<FeatureInfo note={KEY} className="ml-2" />);

        expect(screen.getByTestId(TRIGGER).className).toContain("ml-2");
    });
});

describe("FEATURE_NOTES copy rules", () => {
    const keys = Object.keys(FEATURE_NOTES) as TFeatureNoteKey[];

    it("holds at least the three seeded entries", () => {
        expect(keys.length).toBeGreaterThanOrEqual(3);
    });

    it.each(keys)("%s is one sentence under 120 characters that names its feature", (key) => {
        const { feature, note } = FEATURE_NOTES[key];

        expect(feature.length).toBeGreaterThan(0);
        expect(note.length).toBeLessThan(120);
        expect(note.endsWith(".")).toBe(true);
        expect(note.match(/[.!?]/g)?.length).toBe(1);
    });
});
