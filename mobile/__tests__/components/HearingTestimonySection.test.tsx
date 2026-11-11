// @lat: [[unlinked-bill-presentation#Cross-platform parity in unlinked presentation]]

import React from "react";
import { fireEvent, render, screen } from "@testing-library/react-native";
import * as WebBrowser from "expo-web-browser";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { HearingTestimonySection } from "../../src/components/HearingTestimonySection";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

jest.mock("expo-web-browser", () => ({
    openBrowserAsync: jest.fn(async () => ({ type: "dismiss" })),
}));

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn().mockResolvedValue(undefined),
    ImpactFeedbackStyle: { Light: "light" },
}));

const mockShareBill = jest.fn();
jest.mock("../../src/hooks/useShareBill", () => ({
    useShareBill: () => ({
        shareBill: mockShareBill,
    }),
}));

const safeBill = {
    id: 1,
    title: "Test Bill",
    link: "https://mgaleg.maryland.gov/bills/HB1234",
};

const unsafeBill = {
    id: 2,
    title: "Bad Bill",
    link: "http://evil.example.com/foo",
};

const unlinkedBill = {
    id: 3,
    title: "Unlinked Bill",
    link: null,
};

const genericSearchBill = {
    id: 4,
    title: "Generic Search Bill",
    link: "https://baltimore.legistar.com/LegislationSearch.aspx",
};

const userVote = { support: "FOR" as const };

const ALL_GENERIC_PORTAL_URLS = [
    "https://baltimore.legistar.com",
    "https://baltimore.legistar.com/legislationsearch.aspx",
    "https://congress.gov",
    "https://www.congress.gov",
    "https://mgaleg.maryland.gov",
    "https://mgaleg.maryland.gov/mgawebsite",
];

const wrap = (
    bill: { id?: number; title?: string; link?: string | null },
    opts?: {
        userVote?: typeof userVote | null;
        swayLocaleSlug?: string;
        allowedSourceHosts?: readonly string[];
        genericPortalUrls?: string[];
    },
) =>
    render(
        <ThemeProvider initialMode="light">
            <HearingTestimonySection
                bill={bill}
                userVote={opts?.userVote ?? null}
                swayLocaleSlug={opts?.swayLocaleSlug ?? "baltimore-maryland-united_states"}
                allowedSourceHosts={opts?.allowedSourceHosts}
                genericPortalUrls={opts?.genericPortalUrls ?? ALL_GENERIC_PORTAL_URLS}
            />
        </ThemeProvider>,
    );

describe("HearingTestimonySection", () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    test("Test 1: renders 'Take the next step' header", () => {
        wrap(safeBill);
        expect(screen.getByText("Take the next step")).toBeTruthy();
    });

    test("Test 2: with bill.link present, renders an 'Open bill' Pressable with accessibilityRole=link", () => {
        wrap(safeBill);
        const openBillBtn = screen.getByTestId("open-bill-link");
        expect(openBillBtn).toBeTruthy();
        expect(openBillBtn.props.accessibilityRole).toBe("link");
    });

    test("Test 3: pressing 'Open bill' calls openBrowserAsync with bill.link", async () => {
        wrap(safeBill);
        fireEvent.press(screen.getByTestId("open-bill-link"));
        expect(WebBrowser.openBrowserAsync).toHaveBeenCalledWith(
            safeBill.link,
            expect.objectContaining({ dismissButtonStyle: "done" }),
        );
    });

    test("Test 4: with a bill.link that is not https, shows the unavailable notice instead of a dead button", () => {
        wrap(unsafeBill);
        expect(screen.queryByTestId("open-bill-link")).toBeNull();
        expect(screen.getByTestId("no-source-link").props.children).toBe(PARITY_COPY.bill.officialSourceUnavailable);
        expect(WebBrowser.openBrowserAsync).not.toHaveBeenCalled();
    });

    test("Test 5: with userVote present, renders 'Compare with representatives' and 'Vote on past legislation' CTAs", () => {
        wrap(safeBill, { userVote });
        expect(screen.getByText("Compare with representatives")).toBeTruthy();
        expect(screen.getByText("Vote on past legislation")).toBeTruthy();
    });

    test("Test 6: without userVote, those CTAs are not rendered", () => {
        wrap(safeBill, { userVote: null });
        expect(screen.queryByText("Compare with representatives")).toBeNull();
        expect(screen.queryByText("Vote on past legislation")).toBeNull();
    });

    test("Test 7: with null bill.link, suppresses 'open-bill-link' and renders 'no-source-link' copy", () => {
        wrap(unlinkedBill);
        expect(screen.queryByTestId("open-bill-link")).toBeNull();
        const notice = screen.getByTestId("no-source-link");
        expect(notice).toBeTruthy();
        expect(notice.props.children).toBe(PARITY_COPY.bill.officialSourceUnavailable);
    });

    test("Test 8: with generic search URL, suppresses 'open-bill-link' and renders 'no-source-link' copy", () => {
        wrap(genericSearchBill);
        expect(screen.queryByTestId("open-bill-link")).toBeNull();
        const notice = screen.getByTestId("no-source-link");
        expect(notice).toBeTruthy();
        expect(notice.props.children).toBe(PARITY_COPY.bill.officialSourceUnavailable);
    });

    test("Test 9: with trailing slash generic portal URL, suppresses 'open-bill-link' and renders 'no-source-link' copy", () => {
        wrap({ id: 5, title: "Trailing Slash Bill", link: "https://mgaleg.maryland.gov/mgawebsite/" });
        expect(screen.queryByTestId("open-bill-link")).toBeNull();
        const notice = screen.getByTestId("no-source-link");
        expect(notice).toBeTruthy();
        expect(notice.props.children).toBe(PARITY_COPY.bill.officialSourceUnavailable);
    });

    test("Test 10: with generic search URL containing query parameters, suppresses 'open-bill-link' and renders 'no-source-link' copy", () => {
        wrap({
            id: 6,
            title: "Query Param Search Bill",
            link: "https://baltimore.legistar.com/LegislationSearch.aspx?Mode=Advanced",
        });
        expect(screen.queryByTestId("open-bill-link")).toBeNull();
        const notice = screen.getByTestId("no-source-link");
        expect(notice).toBeTruthy();
        expect(notice.props.children).toBe(PARITY_COPY.bill.officialSourceUnavailable);
    });

    test("Test 11: with generic search URL using http protocol variation, suppresses 'open-bill-link' and renders 'no-source-link' copy", () => {
        wrap({
            id: 7,
            title: "Http Search Bill",
            link: "http://baltimore.legistar.com/LegislationSearch.aspx",
        });
        expect(screen.queryByTestId("open-bill-link")).toBeNull();
        const notice = screen.getByTestId("no-source-link");
        expect(notice).toBeTruthy();
        expect(notice.props.children).toBe(PARITY_COPY.bill.officialSourceUnavailable);
    });

    test("Test 12: with generic portal root URL using mixed casing, suppresses 'open-bill-link' and renders 'no-source-link' copy", () => {
        wrap({
            id: 8,
            title: "Mixed Case Portal Bill",
            link: "https://Congress.gov",
        });
        expect(screen.queryByTestId("open-bill-link")).toBeNull();
        const notice = screen.getByTestId("no-source-link");
        expect(notice).toBeTruthy();
        expect(notice.props.children).toBe(PARITY_COPY.bill.officialSourceUnavailable);
    });

    test("Test 13: opens configured new official host via allowedSourceHosts", async () => {
        wrap(
            { id: 9, title: "Annapolis Bill", link: "https://annapolis.gov/bills/101" },
            { allowedSourceHosts: ["annapolis.gov"] },
        );
        fireEvent.press(screen.getByTestId("open-bill-link"));
        expect(WebBrowser.openBrowserAsync).toHaveBeenCalledWith(
            "https://annapolis.gov/bills/101",
            expect.objectContaining({ dismissButtonStyle: "done" }),
        );
    });

    test("Test 14: rejects lookalike suffix for configured host", () => {
        wrap(
            { id: 10, title: "Spoofed Bill", link: "https://fakeannapolis.gov/bills/101" },
            { allowedSourceHosts: ["annapolis.gov"] },
        );
        expect(screen.queryByTestId("open-bill-link")).toBeNull();
        expect(screen.getByTestId("no-source-link")).toBeTruthy();
        expect(WebBrowser.openBrowserAsync).not.toHaveBeenCalled();
    });

    test("Test 15: rejects unsupported scheme for configured host", () => {
        wrap(
            { id: 11, title: "Insecure Bill", link: "http://annapolis.gov/bills/101" },
            { allowedSourceHosts: ["annapolis.gov"] },
        );
        expect(screen.queryByTestId("open-bill-link")).toBeNull();
        expect(screen.getByTestId("no-source-link")).toBeTruthy();
        expect(WebBrowser.openBrowserAsync).not.toHaveBeenCalled();
    });

    test("Test 16: missing configuration degrades explicitly without opening unapproved host", () => {
        wrap(
            { id: 12, title: "Unknown Host Bill", link: "https://unknowncity.gov/bills/101" },
            { allowedSourceHosts: undefined },
        );
        expect(screen.queryByTestId("open-bill-link")).toBeNull();
        expect(screen.getByTestId("no-source-link")).toBeTruthy();
        expect(WebBrowser.openBrowserAsync).not.toHaveBeenCalled();
    });

    test("Test 19: every rendered open-bill-link button opens the link when pressed", () => {
        const cases = [
            { id: 13, title: "A", link: "https://mgaleg.maryland.gov/bills/HB1" },
            { id: 14, title: "B", link: "https://baltimore.legistar.com/LegislationDetail.aspx?ID=1" },
        ];
        for (const bill of cases) {
            const { unmount } = wrap(bill);
            fireEvent.press(screen.getByTestId("open-bill-link"));
            expect(WebBrowser.openBrowserAsync).toHaveBeenLastCalledWith(bill.link, expect.anything());
            unmount();
        }
    });

    test("Test 20: the link label wraps instead of overflowing for a long locale name", () => {
        wrap(safeBill, { swayLocaleSlug: "los_angeles-california-united_states" });
        const label = screen.getByText("View on LACityClerk Connect");
        expect(label.props.className).toContain("shrink");
        expect(label.props.className).toContain("text-center");
    });

    test("Test 17: with bill.id present, renders 'Share bill' Pressable with testID='share-bill-button' and triggers share on press", () => {
        wrap(safeBill);
        const shareBtn = screen.getByTestId("share-bill-button");
        expect(shareBtn).toBeTruthy();
        expect(shareBtn.props.accessibilityRole).toBe("button");
        expect(shareBtn.props.accessibilityLabel).toBe(PARITY_COPY.bill.shareBill);
        expect(screen.getByText(PARITY_COPY.bill.shareBill)).toBeTruthy();
        expect(screen.getByTestId("lucide-share2")).toBeTruthy();

        fireEvent.press(shareBtn);
        expect(mockShareBill).toHaveBeenCalledWith(safeBill);
    });

    test("Test 18: without bill.id, does not render 'share-bill-button'", () => {
        wrap({ title: "No ID Bill", link: null });
        expect(screen.queryByTestId("share-bill-button")).toBeNull();
    });
});
