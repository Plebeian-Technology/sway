import React from "react";
import { StyleSheet } from "react-native";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react-native";

const mockGet = jest.fn();
jest.mock("../../src/api/client", () => ({
    apiClient: { get: (...args: unknown[]) => mockGet(...args) },
}));

import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { PublicTestimonySection } from "../../src/components/PublicTestimonySection";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import type { PublicTestimonyCounts, PublicTestimonyLetter } from "../../src/types/bill";

const COPY = PARITY_COPY.publicTestimony;

const COUNTS: PublicTestimonyCounts = { total: 25, support: 15, oppose: 7, neutral: 3 };

const LETTERS: PublicTestimonyLetter[] = [
    {
        position: 1,
        label: "Constituent Letter #1",
        stance: "support",
        body_text: "I strongly support this bill for clean neighborhood air.",
    },
    {
        position: 2,
        label: "Constituent Letter #2",
        stance: "oppose",
        body_text: "I oppose the fee increases mandated by this bill.",
    },
    {
        position: 3,
        label: "Constituent Letter #3",
        stance: "neutral",
        body_text: "Neutral comments on procedural timelines.",
    },
];

type SectionProps = React.ComponentProps<typeof PublicTestimonySection>;

function sectionProps(overrides: Partial<SectionProps> = {}): SectionProps {
    return { billId: 42, counts: COUNTS, isSignedIn: true, ...overrides };
}

const ui = (props: SectionProps) => (
    <ThemeProvider initialMode="light">
        <PublicTestimonySection {...props} />
    </ThemeProvider>
);

const renderSection = (overrides: Partial<SectionProps> = {}) => render(ui(sectionProps(overrides)));

const pill = (stance: "support" | "oppose" | "neutral") =>
    screen.getByTestId(`public-testimony-section-pill-${stance}`);

describe("PublicTestimonySection", () => {
    // @lat: [[testimony-letters#Reading the letters inside a testimony bundle#Browsing constituent testimony in the modal]]
    beforeEach(() => {
        mockGet.mockReset();
        mockGet.mockResolvedValue(LETTERS);
    });

    describe("renders nothing", () => {
        test("when the reader is signed out, even if counts are present", () => {
            const { toJSON } = renderSection({ isSignedIn: false });
            expect(toJSON()).toBeNull();
        });

        test("when counts is null", () => {
            const { toJSON } = renderSection({ counts: null });
            expect(toJSON()).toBeNull();
        });

        test("when counts is undefined", () => {
            const { toJSON } = renderSection({ counts: undefined });
            expect(toJSON()).toBeNull();
        });

        test("when every count is zero", () => {
            const { toJSON } = renderSection({ counts: { total: 0, support: 0, oppose: 0, neutral: 0 } });
            expect(toJSON()).toBeNull();
        });

        test("without requesting any letters", async () => {
            renderSection({ isSignedIn: false });
            renderSection({ counts: null });
            await act(async () => {});
            expect(mockGet).not.toHaveBeenCalled();
        });
    });

    describe("with counts", () => {
        test("shows the heading, the letter total and a pill per stance", () => {
            renderSection();

            expect(screen.getByTestId("public-testimony-section")).toBeTruthy();
            expect(screen.getByText(COPY.section.heading)).toBeTruthy();
            expect(screen.getByText(COPY.section.subtitle(25))).toBeTruthy();
            expect(screen.getByText(`15 ${COPY.section.supportPill}`)).toBeTruthy();
            expect(screen.getByText(`7 ${COPY.section.opposePill}`)).toBeTruthy();
            expect(screen.getByText(`3 ${COPY.section.neutralPill}`)).toBeTruthy();
            expect(screen.getByText(COPY.section.browseButton)).toBeTruthy();
        });

        test("still shows a pill for a stance with no letters", () => {
            renderSection({ counts: { total: 4, support: 4, oppose: 0, neutral: 0 } });

            expect(screen.getByText(`0 ${COPY.section.opposePill}`)).toBeTruthy();
            expect(screen.getByText(`0 ${COPY.section.neutralPill}`)).toBeTruthy();
        });

        test("uses the given testID as the section root", () => {
            renderSection({ testID: "bill-public-testimony" });
            expect(screen.getByTestId("bill-public-testimony")).toBeTruthy();
            expect(screen.getByTestId("bill-public-testimony-pill-support")).toBeTruthy();
        });

        test("makes every pill a button at least 44pt tall that says what it opens", () => {
            renderSection();

            const expected = {
                support: `View ${COPY.section.supportPill.toLowerCase()} letters, 15`,
                oppose: `View ${COPY.section.opposePill.toLowerCase()} letters, 7`,
                neutral: `View ${COPY.section.neutralPill.toLowerCase()} letters, 3`,
            } as const;
            for (const stance of ["support", "oppose", "neutral"] as const) {
                const node = pill(stance);
                expect(node.props.accessibilityRole).toBe("button");
                expect(node.props.accessibilityLabel).toBe(expected[stance]);
                const style = StyleSheet.flatten(node.props.style) as { minHeight?: number };
                expect(style.minHeight).toBeGreaterThanOrEqual(44);
            }
            const browse = screen.getByTestId("public-testimony-section-browse");
            expect(browse.props.accessibilityRole).toBe("button");
            expect(browse.props.accessibilityLabel).toBe(COPY.section.browseButton);
        });

        test("does not fetch letters or show the sheet until a pill is pressed", async () => {
            renderSection();
            await act(async () => {});

            expect(mockGet).not.toHaveBeenCalled();
            expect(screen.queryByTestId("browse-testimony-sheet-close")).toBeNull();
        });
    });

    describe("opening the sheet", () => {
        test.each([
            ["support", "support"],
            ["oppose", "oppose"],
            ["neutral", "neutral"],
        ] as const)("the %s pill opens the sheet on the %s tab", async (stance, tab) => {
            renderSection({ billTitle: "Ordinance on Street Trees" });

            fireEvent.press(pill(stance));

            expect(screen.getByTestId("browse-testimony-sheet-close")).toBeTruthy();
            expect(screen.getByText("Ordinance on Street Trees")).toBeTruthy();
            expect(screen.getByTestId(`browse-testimony-sheet-tab-${tab}`).props.accessibilityState).toMatchObject({
                selected: true,
            });
            const mine = LETTERS.find((letter) => letter.stance === tab);
            expect(await screen.findByTestId(`testimony-letter-${mine?.position}`)).toBeTruthy();
            expect(screen.queryAllByTestId(/^testimony-letter-\d+$/)).toHaveLength(1);
            expect(mockGet).toHaveBeenCalledTimes(1);
        });

        test("the Browse button opens the sheet on the All tab and loads the letters on demand", async () => {
            renderSection();

            fireEvent.press(screen.getByTestId("public-testimony-section-browse"));

            expect(screen.getByTestId("browse-testimony-sheet-tab-all").props.accessibilityState).toMatchObject({
                selected: true,
            });
            expect(screen.getByTestId("browse-testimony-sheet-loading")).toBeTruthy();
            expect(await screen.findByText("I oppose the fee increases mandated by this bill.")).toBeTruthy();
            expect(mockGet).toHaveBeenCalledWith("/bills/42/public_testimony_letters", {
                signal: expect.any(AbortSignal),
            });
        });

        test("opens on the pressed stance each time, not the last one used", async () => {
            renderSection();
            fireEvent.press(pill("support"));
            await screen.findByText("I strongly support this bill for clean neighborhood air.");
            fireEvent.press(screen.getByTestId("browse-testimony-sheet-close"));
            expect(screen.queryByTestId("browse-testimony-sheet-close")).toBeNull();

            fireEvent.press(screen.getByTestId("public-testimony-section-browse"));

            expect(screen.getByTestId("browse-testimony-sheet-tab-all").props.accessibilityState).toMatchObject({
                selected: true,
            });
            expect(await screen.findByTestId("testimony-letter-3")).toBeTruthy();
            expect(mockGet).toHaveBeenCalledTimes(2);
        });

        test("shows an error with a retry when the request fails, then the letters on retry", async () => {
            mockGet.mockRejectedValueOnce(new Error("offline"));
            renderSection();

            fireEvent.press(screen.getByTestId("public-testimony-section-browse"));
            expect(await screen.findByTestId("browse-testimony-sheet-error")).toBeTruthy();

            fireEvent.press(screen.getByText(PARITY_COPY.legislators.historyRetry));

            expect(await screen.findByText("Neutral comments on procedural timelines.")).toBeTruthy();
            expect(mockGet).toHaveBeenCalledTimes(2);
        });

        test("aborts the request when the sheet is closed", async () => {
            let signal: AbortSignal | undefined;
            mockGet.mockImplementation((_path: string, opts: { signal: AbortSignal }) => {
                signal = opts.signal;
                return new Promise(() => {});
            });
            renderSection();

            fireEvent.press(screen.getByTestId("public-testimony-section-browse"));
            await waitFor(() => expect(signal).toBeDefined());
            fireEvent.press(screen.getByTestId("browse-testimony-sheet-close"));

            expect(signal?.aborted).toBe(true);
        });
    });

    describe("when the reader signs out", () => {
        test("closes an open sheet, removes the section and does not reopen on sign-in", async () => {
            const view = renderSection();
            fireEvent.press(pill("support"));
            await screen.findByText("I strongly support this bill for clean neighborhood air.");

            view.rerender(ui(sectionProps({ isSignedIn: false })));
            expect(view.toJSON()).toBeNull();

            view.rerender(ui(sectionProps({ isSignedIn: true })));
            expect(screen.getByTestId("public-testimony-section")).toBeTruthy();
            expect(screen.queryByTestId("browse-testimony-sheet-close")).toBeNull();
        });
    });
});
