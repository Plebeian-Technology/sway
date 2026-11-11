// @lat: [[partner-article-engagement#Administrative interface]]
import { render, screen } from "@testing-library/react";
import React from "react";
import { describe, expect, it, vi } from "vitest";

vi.mock("@inertiajs/react", () => ({
    Link: ({ children, href, className }: { children: React.ReactNode; href: string; className?: string }) => (
        <a href={href} className={className}>
            {children}
        </a>
    ),
    router: {
        get: vi.fn<(...args: unknown[]) => void>(),
    },
    usePoll: vi.fn<() => void>(),
}));

import PartnerReportsIndex, { type IPartnerReport } from "app/frontend/pages/admin/PartnerReports/Index";

const sampleReportWithSuppression: IPartnerReport = {
    partner_slug: "the-banner",
    partner_name: "The Baltimore Banner",
    articles_count: 2,
    bills_count: 2,
    total_clicks: 150,
    total_registrations: 25,
    total_votes: 3,
    pro_percentage: null,
    con_percentage: null,
    sentiment_suppressed: true,
    articles: [
        {
            id: 101,
            bill_id: 42,
            bill_title: "Affordable Housing Act",
            article_title: "Council Weighs Affordable Housing Mandate",
            article_url: "https://thebaltimorebanner.com/housing-bill",
            published_at: "2026-09-01T12:00:00Z",
            clicks_count: 100,
            registrations_count: 20,
            votes_count: 2,
            sentiment_suppressed: true,
            pro_votes_count: null,
            con_votes_count: null,
        },
        {
            id: 102,
            bill_id: 43,
            bill_title: "Transit Equity Resolution",
            article_title: "Bus Lane Expansion Stirs Debate",
            article_url: "https://thebaltimorebanner.com/transit-equity",
            published_at: "2026-09-05T15:30:00Z",
            clicks_count: 50,
            registrations_count: 5,
            votes_count: 1,
            sentiment_suppressed: true,
            pro_votes_count: null,
            con_votes_count: null,
        },
    ],
};

const sampleReportUnsuppressed: IPartnerReport = {
    partner_slug: "maryland-matters",
    partner_name: "Maryland Matters",
    articles_count: 1,
    bills_count: 1,
    total_clicks: 220,
    total_registrations: 45,
    total_votes: 18,
    pro_percentage: 72.2,
    con_percentage: 27.8,
    sentiment_suppressed: false,
    articles: [
        {
            id: 201,
            bill_id: 88,
            bill_title: "Clean Energy Standard Bill",
            article_title: "State Senate Debates Wind and Solar Targets",
            article_url: "https://marylandmatters.org/clean-energy",
            published_at: "2026-09-08T09:00:00Z",
            clicks_count: 220,
            registrations_count: 45,
            votes_count: 18,
            sentiment_suppressed: false,
            pro_votes_count: 13,
            con_votes_count: 5,
        },
    ],
};

describe("PartnerReportsIndex component", () => {
    it("renders partner statistics and article lists for multiple reports", () => {
        render(<PartnerReportsIndex reports={[sampleReportWithSuppression, sampleReportUnsuppressed]} />);

        // Partner names in table and headers
        expect(screen.getAllByText("The Baltimore Banner").length).toBeGreaterThanOrEqual(1);
        expect(screen.getByText("the-banner")).toBeInTheDocument();
        expect(screen.getAllByText("Maryland Matters").length).toBeGreaterThanOrEqual(1);
        expect(screen.getByText("maryland-matters")).toBeInTheDocument();

        // Aggregate statistics in summary cards:
        // Clicks: 150 + 220 = 370
        expect(screen.getByText("370")).toBeInTheDocument();
        // Registrations: 25 + 45 = 70
        expect(screen.getByText("70")).toBeInTheDocument();
        // Votes: 3 + 18 = 21
        expect(screen.getByText("21")).toBeInTheDocument();

        // Articles in table
        expect(screen.getByText("Council Weighs Affordable Housing Mandate")).toBeInTheDocument();
        expect(screen.getByText("Bus Lane Expansion Stirs Debate")).toBeInTheDocument();
        expect(screen.getByText("State Senate Debates Wind and Solar Targets")).toBeInTheDocument();

        // Link to article
        const link = screen.getByRole("link", { name: /Council Weighs Affordable Housing Mandate/i });
        expect(link).toHaveAttribute("href", "https://thebaltimorebanner.com/housing-bill");
    });

    it("displays suppression notice when sentiment_suppressed is true (k < 5 protection)", () => {
        render(<PartnerReportsIndex reports={[sampleReportWithSuppression]} />);

        // Should display "Suppressed (k < 5)" badges for aggregate and articles
        const badges = screen.getAllByText("Suppressed (k < 5)");
        expect(badges.length).toBeGreaterThanOrEqual(1);

        // Explanatory note should be visible
        expect(screen.getByText(/k < 5 votes suppresses sentiment to protect voter privacy/i)).toBeInTheDocument();
    });

    it("renders single partner view when report prop is provided", () => {
        render(<PartnerReportsIndex report={sampleReportUnsuppressed} />);

        // Partner name header
        expect(screen.getByRole("heading", { level: 1, name: "Maryland Matters" })).toBeInTheDocument();

        // Partner details
        expect(screen.getByText(/for Maryland Matters \(maryland-matters\)/i)).toBeInTheDocument();
        expect(screen.getByText("← All Partners")).toBeInTheDocument();

        // Metrics for Maryland Matters (present in summary cards and table)
        expect(screen.getAllByText("220").length).toBeGreaterThanOrEqual(1);
        expect(screen.getAllByText("45").length).toBeGreaterThanOrEqual(1);
        expect(screen.getAllByText("18").length).toBeGreaterThanOrEqual(1);
        expect(screen.getByText("72.2% Pro / 27.8% Con")).toBeInTheDocument();

        // Covered article
        expect(screen.getByText("State Senate Debates Wind and Solar Targets")).toBeInTheDocument();
        expect(screen.getByText("13 Pro / 5 Con")).toBeInTheDocument();
    });
});
