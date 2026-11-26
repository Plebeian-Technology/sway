import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";
import { Linking } from "react-native";

import { ApiRequestError } from "../../../src/api/errors";

const mockApiGet = jest.fn();
jest.mock("../../../src/api/client", () => ({
    apiClient: { get: (...args: unknown[]) => mockApiGet(...args) },
}));

jest.mock("../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

import PartnerReportScreen from "../../../src/screens/admin/PartnerReportScreen";

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

const report = {
    partner_slug: "the-banner",
    partner_name: "The Baltimore Banner",
    articles_count: 3,
    bills_count: 2,
    total_clicks: 1500,
    total_registrations: 75,
    total_votes: 8,
    pro_percentage: 75,
    con_percentage: 25,
    articles: [article],
};

const route = { key: "r", name: "AdminPartnerReport" as const, params: { partnerSlug: "the-banner" } };

// @lat: [[mobile-admin-area#The partner report screen]]
describe("PartnerReportScreen", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiGet.mockResolvedValue(report);
    });

    it("renders the headline figures of the report fetched by slug", async () => {
        render(<PartnerReportScreen route={route} />);

        expect(await screen.findByText("The Baltimore Banner")).toBeTruthy();
        expect(mockApiGet).toHaveBeenCalledWith("/admin/partner_reports/the-banner", expect.anything());
        expect(
            screen.getByText(
                "Engagement metrics, voter conversion, and article coverage for The Baltimore Banner (the-banner).",
            ),
        ).toBeTruthy();
        expect(screen.getByText("Articles & Bills")).toBeTruthy();
        expect(screen.getByText("3")).toBeTruthy();
        expect(screen.getByText("Across 2 distinct bills")).toBeTruthy();
        expect(screen.getByText("1,500")).toBeTruthy();
        expect(screen.getByText("75")).toBeTruthy();
        expect(screen.getByText("5.0% click-to-register conversion")).toBeTruthy();
        expect(screen.getByText("Votes Cast")).toBeTruthy();
        expect(screen.getByText("75% Pro / 25% Con")).toBeTruthy();
    });

    it("shows the suppression badge when the partner has fewer than five votes", async () => {
        mockApiGet.mockResolvedValue({ ...report, total_votes: 4, pro_percentage: null, con_percentage: null });
        render(<PartnerReportScreen route={route} />);

        await screen.findByText("The Baltimore Banner");
        expect(screen.getByText("Suppressed (k < 5)")).toBeTruthy();
        expect(screen.queryByText("Constituent votes on covered bills")).toBeNull();
    });

    it("shows the generic votes note when sentiment is unavailable but not suppressed", async () => {
        mockApiGet.mockResolvedValue({ ...report, pro_percentage: null, con_percentage: null });
        render(<PartnerReportScreen route={route} />);

        await screen.findByText("The Baltimore Banner");
        expect(screen.getByText("Constituent votes on covered bills")).toBeTruthy();
    });

    it("lists the covered articles without a partner line and opens the link", async () => {
        const openURL = jest.spyOn(Linking, "openURL").mockResolvedValue(undefined);
        render(<PartnerReportScreen route={route} />);

        fireEvent.press(await screen.findByText("Banner Bill Coverage"));

        expect(openURL).toHaveBeenCalledWith("https://thebaltimorebanner.com/story/1");
        expect(screen.getByText("Bill: Rent Stabilization")).toBeTruthy();
        expect(screen.getByText("Nov 1, 2026")).toBeTruthy();
        expect(screen.getByText("6 Pro / 2 Con")).toBeTruthy();
        expect(screen.getAllByText("The Baltimore Banner")).toHaveLength(1);
        openURL.mockRestore();
    });

    it("shows the empty state when the partner has no articles", async () => {
        mockApiGet.mockResolvedValue({ ...report, articles: [] });
        render(<PartnerReportScreen route={route} />);

        expect(await screen.findByText("No articles recorded for this partner yet.")).toBeTruthy();
    });

    it("shows the server's message when the request fails", async () => {
        mockApiGet.mockRejectedValue(new ApiRequestError("not_found", "Partner not found.", undefined, 404));
        render(<PartnerReportScreen route={route} />);

        await waitFor(() => expect(screen.getByText("Partner not found.")).toBeTruthy());
    });
});
