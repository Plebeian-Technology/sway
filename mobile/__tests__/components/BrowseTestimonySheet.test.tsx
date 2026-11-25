import React from "react";
import { Modal, Platform, StyleSheet } from "react-native";
import { fireEvent, render, screen } from "@testing-library/react-native";

import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { BrowseTestimonySheet, type BrowseTestimonySheetProps } from "../../src/components/BrowseTestimonySheet";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import type { PublicTestimonyCounts, PublicTestimonyLetter, PublicTestimonyStance } from "../../src/types/bill";

const STANCES: PublicTestimonyStance[] = ["support", "oppose", "neutral"];

function makeLetters(total: number): PublicTestimonyLetter[] {
    return Array.from({ length: total }, (_, index) => ({
        position: index + 1,
        label: `Constituent Letter #${index + 1}`,
        stance: STANCES[index % 3],
        body_text: `Body of letter ${index + 1}.`,
    }));
}

function countsFor(letters: PublicTestimonyLetter[]): PublicTestimonyCounts {
    return {
        total: letters.length,
        support: letters.filter((l) => l.stance === "support").length,
        oppose: letters.filter((l) => l.stance === "oppose").length,
        neutral: letters.filter((l) => l.stance === "neutral").length,
    };
}

const LETTERS = makeLetters(25);
const COUNTS = countsFor(LETTERS);

function renderSheet(overrides: Partial<BrowseTestimonySheetProps> = {}) {
    const props: BrowseTestimonySheetProps = {
        visible: true,
        onClose: jest.fn(),
        counts: COUNTS,
        letters: LETTERS,
        error: null,
        onRetry: jest.fn(),
        ...overrides,
    };
    const ui = (p: BrowseTestimonySheetProps) => (
        <ThemeProvider initialMode="light">
            <BrowseTestimonySheet {...p} />
        </ThemeProvider>
    );
    const view = render(ui(props));
    return {
        ...view,
        props,
        rerenderWith: (next: Partial<BrowseTestimonySheetProps>) => view.rerender(ui({ ...props, ...next })),
    };
}

const letterIds = () => screen.queryAllByTestId(/^testimony-letter-\d+$/).map((node) => node.props.testID as string);

describe("BrowseTestimonySheet", () => {
    test("renders nothing while not visible", () => {
        const { toJSON } = renderSheet({ visible: false });
        expect(toJSON()).toBeNull();
    });

    test("shows the title, bill title and total in the header", () => {
        renderSheet({ billTitle: "Ordinance on Street Trees" });

        expect(screen.getByText(PARITY_COPY.publicTestimony.modal.title)).toBeTruthy();
        expect(screen.getByText("Ordinance on Street Trees")).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.publicTestimony.modal.subtitle(25))).toBeTruthy();
    });

    test("lists a tab per stance with its count, All first", () => {
        renderSheet();

        const tabs = screen.getAllByRole("tab");
        expect(tabs.map((tab) => tab.props.accessibilityLabel)).toEqual([
            `${PARITY_COPY.publicTestimony.modal.allTab} (25)`,
            `${PARITY_COPY.publicTestimony.modal.supportTab} (9)`,
            `${PARITY_COPY.publicTestimony.modal.opposeTab} (8)`,
            `${PARITY_COPY.publicTestimony.modal.neutralTab} (8)`,
        ]);
        expect(screen.getByTestId("browse-testimony-sheet-tab-all").props.accessibilityState).toMatchObject({
            selected: true,
        });
    });

    test("opens on the requested stance tab and lists only that stance", () => {
        renderSheet({ initialFilter: "oppose" });

        expect(screen.getByTestId("browse-testimony-sheet-tab-oppose").props.accessibilityState).toMatchObject({
            selected: true,
        });
        expect(letterIds()).toEqual([2, 5, 8, 11, 14, 17, 20, 23].map((n) => `testimony-letter-${n}`));
    });

    test("filters when another tab is chosen", () => {
        renderSheet();

        fireEvent.press(screen.getByTestId("browse-testimony-sheet-tab-neutral"));

        expect(screen.getByTestId("browse-testimony-sheet-tab-neutral").props.accessibilityState).toMatchObject({
            selected: true,
        });
        expect(letterIds()).toHaveLength(8);
        expect(screen.queryByTestId("testimony-letter-1")).toBeNull();
        expect(screen.getByTestId("testimony-letter-3")).toBeTruthy();
    });

    test("shows ten letters at a time and appends ten more on Show more", () => {
        renderSheet();

        expect(letterIds()).toHaveLength(10);
        expect(letterIds()[9]).toBe("testimony-letter-10");

        fireEvent.press(screen.getByText(PARITY_COPY.bill.showMore));
        expect(letterIds()).toHaveLength(20);

        fireEvent.press(screen.getByText(PARITY_COPY.bill.showMore));
        expect(letterIds()).toHaveLength(25);
        expect(screen.queryByText(PARITY_COPY.bill.showMore)).toBeNull();
    });

    test("labels Show more with how many letters remain", () => {
        renderSheet();

        expect(screen.getByTestId("browse-testimony-sheet-more").props.accessibilityLabel).toBe(
            `${PARITY_COPY.bill.showMore}, 15 remaining`,
        );
    });

    test("offers no Show more when everything fits on one page", () => {
        const letters = makeLetters(4);
        renderSheet({ letters, counts: countsFor(letters) });

        expect(letterIds()).toHaveLength(4);
        expect(screen.queryByText(PARITY_COPY.bill.showMore)).toBeNull();
    });

    test("returns to ten letters when the tab changes", () => {
        renderSheet();
        fireEvent.press(screen.getByText(PARITY_COPY.bill.showMore));
        expect(letterIds()).toHaveLength(20);

        fireEvent.press(screen.getByTestId("browse-testimony-sheet-tab-support"));
        expect(letterIds()).toHaveLength(9);
        fireEvent.press(screen.getByTestId("browse-testimony-sheet-tab-all"));
        expect(letterIds()).toHaveLength(10);
    });

    test("shows each letter's label, stance badge and selectable body", () => {
        renderSheet();

        const card = screen.getByTestId("testimony-letter-2");
        expect(card).toBeTruthy();
        expect(screen.getByText("Constituent Letter #2")).toBeTruthy();
        expect(screen.getByTestId("testimony-letter-2-stance")).toBeTruthy();
        expect(screen.getByTestId("testimony-letter-2-stance").props.accessibilityLabel).toBe(
            `${PARITY_COPY.publicTestimony.modal.stancePrefix}: ${PARITY_COPY.publicTestimony.modal.opposeBadge}`,
        );
        expect(screen.getByText("Body of letter 2.").props.selectable).toBe(true);
    });

    test("renders letter text as plain text, never as markup", () => {
        const letters: PublicTestimonyLetter[] = [
            { position: 1, label: "Constituent Letter #1", stance: "support", body_text: "<b>bold</b> & **stars**" },
        ];
        renderSheet({ letters, counts: countsFor(letters) });

        expect(screen.getByText("<b>bold</b> & **stars**")).toBeTruthy();
    });

    test("shows a loading state while the letters are not yet loaded", () => {
        renderSheet({ letters: null });

        expect(screen.getByTestId("browse-testimony-sheet-loading")).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.publicTestimony.modal.loading)).toBeTruthy();
        expect(screen.queryByTestId("browse-testimony-sheet-empty")).toBeNull();
        expect(letterIds()).toHaveLength(0);
    });

    test("shows an error with a retry that calls onRetry", () => {
        const { props } = renderSheet({ letters: null, error: new Error("offline") });

        expect(screen.getByTestId("browse-testimony-sheet-error")).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.publicTestimony.modal.loadError)).toBeTruthy();
        expect(screen.queryByTestId("browse-testimony-sheet-loading")).toBeNull();

        fireEvent.press(screen.getByText(PARITY_COPY.legislators.historyRetry));
        expect(props.onRetry).toHaveBeenCalledTimes(1);
    });

    test("never shows the error message text", () => {
        renderSheet({ letters: null, error: new Error("secret server detail") });

        expect(screen.queryByText(/secret server detail/)).toBeNull();
    });

    test("shows an empty state when the server has no letters", () => {
        renderSheet({ letters: [], counts: { total: 0, support: 0, oppose: 0, neutral: 0 } });

        expect(screen.getByTestId("browse-testimony-sheet-empty")).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.publicTestimony.modal.empty)).toBeTruthy();
    });

    test("shows the empty state for a stance with no letters", () => {
        const letters = makeLetters(3).map((letter) => ({ ...letter, stance: "support" as const }));
        renderSheet({ letters, counts: countsFor(letters), initialFilter: "oppose" });

        expect(screen.getByTestId("browse-testimony-sheet-empty")).toBeTruthy();
        expect(letterIds()).toHaveLength(0);
    });

    test("closes from the Close button", () => {
        const { props } = renderSheet();

        fireEvent.press(screen.getByTestId("browse-testimony-sheet-close"));

        expect(props.onClose).toHaveBeenCalledTimes(1);
    });

    test("closes from the system back gesture through Modal.onRequestClose", () => {
        const { props } = renderSheet();

        screen.UNSAFE_getByType(Modal).props.onRequestClose();

        expect(props.onClose).toHaveBeenCalledTimes(1);
    });

    test("is a swipe-dismissable page sheet on iOS", () => {
        const original = Platform.OS;
        (Platform as { OS: string }).OS = "ios";
        try {
            renderSheet();
            const modal = screen.UNSAFE_getByType(Modal);
            expect(modal.props.presentationStyle).toBe("pageSheet");
            expect(modal.props.allowSwipeDismissal).toBe(true);
        } finally {
            (Platform as { OS: string }).OS = original;
        }
    });

    test("keeps the Close button and every tab at least 44pt tall", () => {
        renderSheet();

        const heights = [
            "browse-testimony-sheet-close",
            "browse-testimony-sheet-tab-all",
            "browse-testimony-sheet-tab-support",
            "browse-testimony-sheet-tab-oppose",
            "browse-testimony-sheet-tab-neutral",
            "browse-testimony-sheet-more",
        ].map((id) => {
            const style = StyleSheet.flatten(screen.getByTestId(id).props.style) as { minHeight?: number };
            return style.minHeight ?? 0;
        });
        for (const height of heights) expect(height).toBeGreaterThanOrEqual(44);
    });

    test("starts from the requested tab and first page again each time it opens", () => {
        const view = renderSheet({ initialFilter: "support" });
        fireEvent.press(screen.getByTestId("browse-testimony-sheet-tab-all"));
        fireEvent.press(screen.getByText(PARITY_COPY.bill.showMore));
        expect(letterIds()).toHaveLength(20);

        view.rerenderWith({ visible: false });
        view.rerenderWith({ visible: true, initialFilter: "oppose" });

        expect(screen.getByTestId("browse-testimony-sheet-tab-oppose").props.accessibilityState).toMatchObject({
            selected: true,
        });
        expect(letterIds()).toHaveLength(8);
    });

    test("offers no stance or Remove controls without letter editing", () => {
        renderSheet();

        expect(screen.queryByTestId("testimony-letter-1-set-oppose")).toBeNull();
        expect(screen.queryByTestId("testimony-letter-1-remove")).toBeNull();
    });

    test("letter editing offers each stance and Remove, and reports which letter was pressed", () => {
        const onSetStance = jest.fn();
        const onRemove = jest.fn();
        renderSheet({ letterEditing: { onSetStance, onRemove, busy: false, error: null } });

        expect(screen.getByTestId("testimony-letter-1-set-support").props.accessibilityState).toEqual(
            expect.objectContaining({ selected: true }),
        );
        fireEvent.press(screen.getByTestId("testimony-letter-1-set-oppose"));
        fireEvent.press(screen.getByTestId("testimony-letter-2-remove"));

        expect(onSetStance).toHaveBeenCalledWith(1, "oppose");
        expect(onRemove).toHaveBeenCalledWith(2);
    });
});
