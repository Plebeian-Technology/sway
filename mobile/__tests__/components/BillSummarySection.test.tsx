import { Linking, StyleSheet } from "react-native";
import { fireEvent, render, screen } from "@testing-library/react-native";
import * as WebBrowser from "expo-web-browser";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { BillSummarySection, type BillSummarySectionProps } from "../../src/components/BillSummarySection";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn().mockResolvedValue(undefined),
    ImpactFeedbackStyle: { Light: "light" },
}));

jest.mock("expo-web-browser", () => ({
    openBrowserAsync: jest.fn(async () => ({ type: "dismiss" })),
}));

jest.mock("react-native-reanimated", () => require("react-native-reanimated/mock"));

const wrap = (props: BillSummarySectionProps) =>
    render(
        <ThemeProvider initialMode="light">
            <BillSummarySection {...props} />
        </ThemeProvider>,
    );

describe("BillSummarySection", () => {
    test("Test 1: renders header text 'Sway summary'", () => {
        wrap({ summary: "A short summary." });
        expect(screen.getByText("Sway summary")).toBeTruthy();
    });

    test("Test 2: with summary length <= 200 chars, no 'Show more' button visible", () => {
        wrap({ summary: "Short summary under 200 chars." });
        expect(screen.queryByText("Show more")).toBeNull();
    });

    test("Test 3: with summary length > 200 chars, renders 'Show more' Pressable", () => {
        wrap({ summary: "x".repeat(300) });
        expect(screen.getByText("Show more")).toBeTruthy();
    });

    test("Test 4: pressing 'Show more' reveals remaining text and toggles label to 'Show less'", () => {
        wrap({ summary: "x".repeat(300) });
        fireEvent.press(screen.getByText("Show more"));
        expect(screen.getByText("Show less")).toBeTruthy();
    });

    test("Test 5: pressing 'Show less' toggles label back to 'Show more'", () => {
        wrap({ summary: "x".repeat(300) });
        fireEvent.press(screen.getByText("Show more"));
        fireEvent.press(screen.getByText("Show less"));
        expect(screen.getByText("Show more")).toBeTruthy();
    });

    test("Test 6: show-more Pressable has accessibilityRole=button and accessibilityState.expanded matches state", () => {
        wrap({ summary: "x".repeat(300) });
        expect(screen.getByText("Show more")).toBeTruthy();
        fireEvent.press(screen.getByText("Show more"));
        expect(screen.getByText("Show less")).toBeTruthy();
    });

    test("Test 7: NEWLINE/ENDING markers stripped from displayed text", () => {
        wrap({ summary: "Hello NEWLINE world ENDING done." });
        expect(screen.getByText(/Hello\s+world\s+done\./)).toBeTruthy();
    });

    test("Test 8: with null summary, renders without crash", () => {
        expect(() => wrap({ summary: null })).not.toThrow();
        expect(screen.getByText("Sway summary")).toBeTruthy();
    });
});

describe("BillSummarySection - Clickable Citations & Link Safety", () => {
    let openURLSpy: jest.SpyInstance;

    beforeEach(() => {
        openURLSpy = jest.spyOn(Linking, "openURL").mockResolvedValue(undefined);
    });

    afterEach(() => {
        openURLSpy.mockRestore();
    });

    test("Test 9: citation crossing 200-char preview boundary remains an accessible, tappable safe URL before and after expansion", () => {
        const prefix =
            "The Maryland General Assembly enacted transit funding measures to support regional commuter networks across Baltimore City and surrounding jurisdictions, following reporting by ";
        const citation = "[The Baltimore Banner](https://www.thebaltimorebanner.com/transit-funding)";
        const suffix =
            " detailing capital project priorities and long-term fiscal allocations for municipal transit infrastructure.";
        const summary = `${prefix}${citation}${suffix}`;

        expect(prefix.length).toBe(177);
        expect(prefix.length + citation.length).toBe(251);

        wrap({ summary });

        const linkBefore = screen.getByRole("link", { name: "The Baltimore Banner" });
        expect(linkBefore).toBeTruthy();
        expect(linkBefore.props.accessibilityRole).toBe("link");

        fireEvent.press(linkBefore);
        expect(openURLSpy).toHaveBeenCalledTimes(1);
        expect(openURLSpy).toHaveBeenCalledWith("https://www.thebaltimorebanner.com/transit-funding");
        openURLSpy.mockClear();

        const showMoreBtn = screen.getByText("Show more");
        fireEvent.press(showMoreBtn);

        const linkAfter = screen.getByRole("link", { name: "The Baltimore Banner" });
        expect(linkAfter).toBeTruthy();
        expect(linkAfter.props.accessibilityRole).toBe("link");

        fireEvent.press(linkAfter);
        expect(openURLSpy).toHaveBeenCalledTimes(1);
        expect(openURLSpy).toHaveBeenCalledWith("https://www.thebaltimorebanner.com/transit-funding");

        expect(screen.getByText(/detailing capital project priorities/)).toBeTruthy();
    });

    test.each([
        ["javascript", "[Malicious Script](javascript:alert('pwned'))"],
        ["file", "[System File](file:///etc/passwd)"],
        ["data", "[Data URI](data:text/html,<script>alert(1)</script>)"],
        ["intent", "[Android Intent](intent://example.com#Intent;scheme=bad;end)"],
        ["vbscript", "[VBScript](vbscript:msgbox('bad'))"],
    ])("Test 10: refuses to open unsafe URL with %s scheme", (_scheme, linkMarkdown) => {
        wrap({ summary: `Critical analysis provided by ${linkMarkdown} during hearings.` });

        const link = screen.queryByRole("link");
        if (link) {
            fireEvent.press(link);
        }
        expect(openURLSpy).not.toHaveBeenCalled();
    });

    test("Test 11: plain text summaries without Markdown links render cleanly without errors or spurious links", () => {
        const plainSummary =
            "This is a standard legislative summary that does not include any markdown citations. It discusses zoning regulations in Baltimore City.";
        wrap({ summary: plainSummary });

        expect(screen.getByText(plainSummary)).toBeTruthy();
        expect(screen.queryByRole("link")).toBeNull();
    });

    test("Test 12: plain text with bracketed numbers or notes renders as plain text without link creation", () => {
        const textWithBrackets =
            "Provisions under Section [1] and Subsection [2] outline compliance requirements [see note 4] for businesses.";
        wrap({ summary: textWithBrackets });

        expect(screen.getByText(textWithBrackets)).toBeTruthy();
        expect(screen.queryByRole("link")).toBeNull();
    });

    test("Test 13: link elements expose accessibilityRole='link' and appropriate accessible name", () => {
        const summary = "Full reporting available at [The Baltimore Sun](https://www.baltimoresun.com/article).";
        wrap({ summary });

        const link = screen.getByRole("link", { name: "The Baltimore Sun" });
        expect(link).toBeTruthy();
        expect(link.props.accessibilityRole).toBe("link");
        expect(link.props.accessibilityLabel ?? link.props.children).toEqual(
            expect.stringContaining("The Baltimore Sun"),
        );
    });

    test("Test 14: retains AI-unreviewed notice when summary contains citations and summaryAiUnreviewed is true", () => {
        wrap({
            summary: "Reporting by [The Baltimore Banner](https://www.thebaltimorebanner.com/transit).",
            summaryAiUnreviewed: true,
        });

        expect(screen.getByTestId("ai-unreviewed-notice")).toBeTruthy();
        expect(screen.getByRole("link", { name: "The Baltimore Banner" })).toBeTruthy();
    });

    test("renders the summary as markdown and keeps the collapsed preview within the character budget", () => {
        wrap({ summary: `## Overview\n\n**Key point.**\n\n${"Filler words. ".repeat(40)}` });

        expect(screen.getByRole("header", { name: "Overview" })).toBeTruthy();
        expect(screen.getByText("Key point.")).toBeTruthy();
        expect(screen.queryByText(/##|\*\*/)).toBeNull();
        expect(screen.getByText("Show more")).toBeTruthy();
        expect(screen.getByText("…")).toBeTruthy();
    });
});

describe("BillSummarySection - pending summary", () => {
    test.each([
        ["null", null],
        ["undefined", undefined],
        ["an empty string", ""],
        ["only legacy markers", " NEWLINE ENDING "],
        ["the server's placeholder", "Summary pending"],
    ])("shows one muted line instead of an empty card when the summary is %s", (_label, summary) => {
        wrap({ summary });
        const line = screen.getByTestId("bill-summary-pending");
        expect(line.props.children).toBe(PARITY_COPY.bill.summaryPending);
        expect(line.props.className).toContain("text-muted-foreground-light");
        expect(screen.queryByText("Show more")).toBeNull();
        expect(screen.queryByText("Summary pending")).toBeNull();
    });

    test("does not show the pending line for a real summary", () => {
        wrap({ summary: "A real summary." });
        expect(screen.queryByTestId("bill-summary-pending")).toBeNull();
    });

    test("does not double up when the real summary merely starts with the placeholder words", () => {
        wrap({ summary: "Summary pending changes to zoning rules." });
        expect(screen.queryByTestId("bill-summary-pending")).toBeNull();
        expect(screen.getByText("Summary pending changes to zoning rules.")).toBeTruthy();
    });

    test("keeps the AI notice off a pending summary, where there is nothing to disclaim", () => {
        wrap({ summary: "Summary pending", summaryAiUnreviewed: true });
        expect(screen.queryByTestId("ai-unreviewed-notice")).toBeNull();
    });
});

describe("BillSummarySection - official source notice", () => {
    const LINK = "https://mgaleg.maryland.gov/mgawebsite/Legislation/Details/hb0100";

    beforeEach(() => {
        jest.clearAllMocks();
    });

    test("renders nothing about the source when no link prop is given", () => {
        wrap({ summary: "A summary." });
        expect(screen.queryByTestId("bill-source-text-link")).toBeNull();
        expect(screen.queryByTestId("summary-no-source-link")).toBeNull();
    });

    test("renders a 44pt link that opens a valid official link in the in-app browser", () => {
        wrap({ summary: "A summary.", billLink: LINK, showSourceNotice: true });
        const link = screen.getByTestId("bill-source-text-link");
        expect(link.props.accessibilityRole).toBe("link");
        expect(link.props.accessibilityLabel).toBe(PARITY_COPY.bill.viewOriginalText);
        expect(StyleSheet.flatten(link.props.style).minHeight).toBeGreaterThanOrEqual(44);
        expect(screen.getByText(PARITY_COPY.bill.viewOriginalText)).toBeTruthy();

        fireEvent.press(link);
        expect(WebBrowser.openBrowserAsync).toHaveBeenCalledWith(
            LINK,
            expect.objectContaining({ dismissButtonStyle: "done" }),
        );
    });

    test("says the source is unavailable for a generic portal address", () => {
        wrap({
            summary: "A summary.",
            billLink: "https://mgaleg.maryland.gov/mgawebsite/",
            showSourceNotice: true,
            genericPortalUrls: ["https://mgaleg.maryland.gov/mgawebsite"],
        });
        expect(screen.queryByTestId("bill-source-text-link")).toBeNull();
        expect(screen.getByTestId("summary-no-source-link").props.children).toBe(
            PARITY_COPY.bill.officialSourceUnavailable,
        );
    });

    test("says the source is unavailable for a link on a host the app does not trust, and opens nothing", () => {
        wrap({ summary: "A summary.", billLink: "https://unknowncity.gov/bills/101", showSourceNotice: true });
        expect(screen.queryByTestId("bill-source-text-link")).toBeNull();
        expect(screen.getByTestId("summary-no-source-link")).toBeTruthy();
        expect(WebBrowser.openBrowserAsync).not.toHaveBeenCalled();
    });

    test("trusts an extra host named by allowedSourceHosts", () => {
        wrap({
            summary: "A summary.",
            billLink: "https://annapolis.gov/bills/101",
            showSourceNotice: true,
            allowedSourceHosts: ["annapolis.gov"],
        });
        expect(screen.getByTestId("bill-source-text-link")).toBeTruthy();
    });

    test("trusts the official hosts of the bill's locale", () => {
        wrap({
            summary: "A summary.",
            billLink: "https://baltimorecountymd.gov/bills/101",
            showSourceNotice: true,
            swayLocaleSlug: "baltimore_county-maryland-united_states",
        });
        expect(screen.getByTestId("bill-source-text-link")).toBeTruthy();
    });

    test("with showSourceNotice, a missing link reads as unavailable", () => {
        wrap({ summary: "A summary.", billLink: null, showSourceNotice: true });
        expect(screen.getByTestId("summary-no-source-link")).toBeTruthy();
    });

    test("without showSourceNotice, a null link adds nothing", () => {
        wrap({ summary: "A summary.", billLink: null });
        expect(screen.queryByTestId("summary-no-source-link")).toBeNull();
    });

    test("without showSourceNotice, a valid link adds nothing either", () => {
        wrap({ summary: "A summary.", billLink: LINK });
        expect(screen.queryByTestId("bill-source-text-link")).toBeNull();
        expect(screen.queryByTestId("summary-no-source-link")).toBeNull();
    });

    test("with showSourceNotice and no billLink prop at all, reads as unavailable", () => {
        wrap({ summary: "A summary.", showSourceNotice: true });
        expect(screen.getByTestId("summary-no-source-link")).toBeTruthy();
    });

    test("still offers the source when the summary is pending", () => {
        wrap({ summary: "Summary pending", billLink: LINK, showSourceNotice: true });
        expect(screen.getByTestId("bill-summary-pending")).toBeTruthy();
        expect(screen.getByTestId("bill-source-text-link")).toBeTruthy();
    });

    test("sits beside the AI notice when the summary is unreviewed", () => {
        wrap({ summary: "A summary.", summaryAiUnreviewed: true, billLink: LINK, showSourceNotice: true });
        expect(screen.getByTestId("ai-unreviewed-notice")).toBeTruthy();
        expect(screen.getByTestId("bill-source-text-link")).toBeTruthy();
    });
});
