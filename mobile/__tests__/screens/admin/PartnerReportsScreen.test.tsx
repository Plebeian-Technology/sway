import React from "react";
import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react-native";
import { Linking } from "react-native";

import { ApiRequestError } from "../../../src/api/errors";

const mockApiGet = jest.fn();
jest.mock("../../../src/api/client", () => ({
    apiClient: { get: (...args: unknown[]) => mockApiGet(...args) },
}));

jest.mock("../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

const mockNavigate = jest.fn();
const mockAddListener = jest.fn(() => jest.fn());
jest.mock("@react-navigation/native", () => ({
    ...jest.requireActual("@react-navigation/native"),
    useNavigation: () => ({ navigate: mockNavigate, addListener: mockAddListener }),
}));

import PartnerReportsScreen from "../../../src/screens/admin/PartnerReportsScreen";

const article = {
    id: 1,
    bill_id: 501,
    bill_title: "Rent Stabilization",
    article_title: "Banner Bill Coverage",
    article_url: "https://thebaltimorebanner.com/story/1",
    published_at: "2026-11-01T12:00:00Z",
    clicks_count: 1200,
    registrations_count: 60,
    votes_count: 8,
    sentiment_suppressed: false,
    pro_votes_count: 6,
    con_votes_count: 2,
};

const bannerReport = {
    partner_slug: "the-banner",
    partner_name: "The Baltimore Banner",
    articles_count: 3,
    bills_count: 2,
    total_clicks: 1500,
    total_registrations: 75,
    total_votes: 8,
    pro_percentage: 75,
    con_percentage: 25,
    articles: [
        article,
        {
            ...article,
            id: 2,
            bill_title: null,
            article_title: "Unsafe Coverage",
            article_url: "javascript:alert(1)",
            published_at: null,
            votes_count: 2,
            sentiment_suppressed: true,
            pro_votes_count: null,
            con_votes_count: null,
        },
    ],
};

const quietReport = {
    partner_slug: "city-paper",
    partner_name: "City Paper",
    articles_count: 1,
    bills_count: 1,
    total_clicks: 10,
    total_registrations: 0,
    total_votes: 9,
    pro_percentage: null,
    con_percentage: null,
    articles: [],
};

// @lat: [[mobile-admin-area#The partner reports screen]]
describe("PartnerReportsScreen", () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    it("lists each partner with its figures and sentiment", async () => {
        mockApiGet.mockResolvedValue([bannerReport, quietReport]);
        render(<PartnerReportsScreen />);

        expect((await screen.findAllByText("The Baltimore Banner")).length).toBeGreaterThan(0);
        expect(screen.getByText("City Paper")).toBeTruthy();
        expect(screen.getByText("the-banner")).toBeTruthy();
        expect(screen.getByText("75% Pro / 25% Con")).toBeTruthy();
        expect(screen.getAllByText("Suppressed (k < 5)").length).toBeGreaterThan(0);
        expect(mockApiGet).toHaveBeenCalledWith("/admin/partner_reports", expect.anything());
    });

    it("shows the headline figures summed across partners", async () => {
        mockApiGet.mockResolvedValue([bannerReport, quietReport]);
        render(<PartnerReportsScreen />);
        await screen.findByTestId("admin-partner-report-the-banner");

        expect(screen.getByText("Total Articles")).toBeTruthy();
        expect(screen.getByText("4")).toBeTruthy();
        expect(screen.getByText("Across 2 partner newsrooms")).toBeTruthy();
        expect(screen.getByText("1,510")).toBeTruthy();
        expect(screen.getByText("Inbound reader referrals from embeds")).toBeTruthy();
        expect(screen.getByText("75")).toBeTruthy();
        expect(screen.getByText("5.0% click-to-register conversion")).toBeTruthy();
        expect(screen.getByText("Votes Cast")).toBeTruthy();
        expect(screen.getByText("Constituent votes on covered bills")).toBeTruthy();
    });

    it("lists the covered articles with partner, bill, date and sentiment", async () => {
        mockApiGet.mockResolvedValue([bannerReport, quietReport]);
        render(<PartnerReportsScreen />);

        expect(await screen.findByText("Banner Bill Coverage")).toBeTruthy();
        expect(screen.getByText("Bill: Rent Stabilization")).toBeTruthy();
        expect(screen.getByText("Nov 1, 2026")).toBeTruthy();
        expect(screen.getByText("6 Pro / 2 Con")).toBeTruthy();
        expect(screen.getByText("Unsafe Coverage")).toBeTruthy();
        expect(within(screen.getByTestId("admin-partner-report-city-paper")).getByText("N/A")).toBeTruthy();
    });

    it("opens a safe article link and gives an unsafe one no link", async () => {
        const openURL = jest.spyOn(Linking, "openURL").mockResolvedValue(undefined);
        mockApiGet.mockResolvedValue([bannerReport]);
        render(<PartnerReportsScreen />);

        fireEvent.press(await screen.findByText("Banner Bill Coverage"));
        expect(openURL).toHaveBeenCalledWith("https://thebaltimorebanner.com/story/1");

        fireEvent.press(screen.getByText("Unsafe Coverage"));
        expect(openURL).toHaveBeenCalledTimes(1);
        openURL.mockRestore();
    });

    it("opens the partner detail by slug when a partner is pressed", async () => {
        mockApiGet.mockResolvedValue([bannerReport, quietReport]);
        render(<PartnerReportsScreen />);

        fireEvent.press(await screen.findByTestId("admin-partner-report-the-banner"));

        expect(mockNavigate).toHaveBeenCalledWith("AdminPartnerReport", { partnerSlug: "the-banner" });
    });

    it("shows empty states when there are no partners and no articles", async () => {
        mockApiGet.mockResolvedValue([]);
        render(<PartnerReportsScreen />);

        expect(await screen.findByText("No partner newsroom data recorded yet.")).toBeTruthy();
        expect(screen.getByText("No articles recorded for this partner yet.")).toBeTruthy();
    });

    it("refetches the list when the screen regains focus", async () => {
        mockApiGet.mockResolvedValue([bannerReport]);
        render(<PartnerReportsScreen />);
        await screen.findByTestId("admin-partner-report-the-banner");
        expect(mockAddListener).toHaveBeenCalledWith("focus", expect.any(Function));
        const calls = mockApiGet.mock.calls.length;

        const onFocus = (mockAddListener.mock.calls as unknown as [string, () => void][])[0][1];
        await act(async () => {
            onFocus();
        });

        await waitFor(() => expect(mockApiGet.mock.calls.length).toBe(calls + 1));
    });

    it("shows the server's message when the request fails", async () => {
        mockApiGet.mockRejectedValue(
            new ApiRequestError("forbidden", "You are not allowed to do that.", undefined, 403),
        );
        render(<PartnerReportsScreen />);

        await waitFor(() => expect(screen.getByText("You are not allowed to do that.")).toBeTruthy());
    });
});
