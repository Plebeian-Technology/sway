import { fireEvent, render, screen } from "@testing-library/react";
import React, { useState } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mockPatch = vi.fn<(url: string, data?: unknown, options?: unknown) => void>();
let mockPageProps: { errors?: Record<string, string>; news_articles?: unknown[] } = {};

vi.mock("@inertiajs/react", () => ({
    router: { patch: (url: string, data?: unknown, options?: unknown) => mockPatch(url, data, options) },
    usePage: () => ({ props: mockPageProps }),
}));

vi.mock("app/frontend/sway_utils", () => ({ notify: vi.fn<(...args: unknown[]) => string>() }));

import LlmSummaryEditableSummary from "app/frontend/components/admin/creator/llm-summary/LlmSummaryEditableSummary";
import ManualNewsEvidenceControls from "app/frontend/components/admin/creator/llm-summary/ManualNewsEvidenceControls";
import type { IAdminBillNewsArticle, ISourceUseInput, NewsUsage } from "app/frontend/types/bill_creator";

const createMockArticle = (overrides: Partial<IAdminBillNewsArticle>): IAdminBillNewsArticle => ({
    id: 1,
    bill_id: 1,
    news_article_id: 1,
    url: "https://example.com/article",
    title: "Example Title",
    source_name: "Example Source",
    domain: "example.com",
    author: "Jane Doe",
    published_at: "2026-09-01T12:00:00Z",
    approved: false,
    review_version: 1,
    stance: null,
    stance_version: 1,
    current_text_version_id: null,
    has_text: false,
    text_digest: null,
    text_origin: "retrieved",
    excerpt: null,
    created_at: "2026-09-01T12:00:00Z",
    updated_at: "2026-09-01T12:00:00Z",
    ...overrides,
});

const sampleArticles: IAdminBillNewsArticle[] = [
    createMockArticle({
        id: 101,
        bill_id: 1,
        news_article_id: 201,
        title: "City Council Approves Transit Plan",
        url: "https://thebaltimorebanner.com/transit-plan",
        source_name: "The Baltimore Banner",
        domain: "thebaltimorebanner.com",
        approved: true,
        has_text: true,
        current_text_version_id: 301,
    }),
    createMockArticle({
        id: 102,
        bill_id: 1,
        news_article_id: 202,
        title: "Sun Report on Roads",
        url: "https://baltimoresun.com/roads",
        source_name: "The Baltimore Sun",
        domain: "baltimoresun.com",
        approved: true,
        has_text: true,
        current_text_version_id: 302,
    }),
    createMockArticle({
        id: 103,
        bill_id: 1,
        news_article_id: 203,
        title: "Unapproved Article",
        url: "https://example.com/unapproved",
        approved: false,
        has_text: true,
        current_text_version_id: 303,
    }),
    createMockArticle({
        id: 104,
        bill_id: 1,
        news_article_id: 204,
        title: "Textless Article",
        url: "https://example.com/textless",
        approved: true,
        has_text: false,
        current_text_version_id: null,
    }),
];

const StatefulControlsWrapper: React.FC<{
    initialSummary?: string;
    initialNewsUsage?: NewsUsage;
    initialSourceUses?: ISourceUseInput[];
    articles?: IAdminBillNewsArticle[];
}> = ({
    initialSummary = "Summary text.",
    initialNewsUsage = "none",
    initialSourceUses = [],
    articles = sampleArticles,
}) => {
    const [summary] = useState(initialSummary);
    const [newsUsage, setNewsUsage] = useState<NewsUsage>(initialNewsUsage);
    const [sourceUses, setSourceUses] = useState<ISourceUseInput[]>(initialSourceUses);

    return (
        <ManualNewsEvidenceControls
            summary={summary}
            newsUsage={newsUsage}
            onChangeNewsUsage={setNewsUsage}
            sourceUses={sourceUses}
            onChangeSourceUses={setSourceUses}
            newsArticles={articles}
        />
    );
};

// @lat: [[news-manual-evidence-ui#Manual evidence review controls]]
describe("Adversarial Empirical Challenges — Add manual summary evidence review controls", () => {
    beforeEach(() => {
        mockPatch.mockReset();
        mockPageProps = { news_articles: sampleArticles };
    });

    describe("Vector 1: Cited mode requires only radio selection (no source-use manifest editor)", () => {
        it("does not render source-use form controls when newsUsage is cited", () => {
            render(
                <ManualNewsEvidenceControls
                    summary="According to [The Baltimore Banner](https://thebaltimorebanner.com/transit-plan), the city council allocated $10 million."
                    newsUsage="cited"
                    onChangeNewsUsage={() => {}}
                    sourceUses={[]}
                    onChangeSourceUses={() => {}}
                    newsArticles={sampleArticles}
                />,
            );

            expect(screen.getByTestId("news-usage-cited")).toBeChecked();
            expect(screen.queryByTestId("news-usage-none-warning")).not.toBeInTheDocument();
            expect(screen.queryByTestId("btn-add-source-use")).not.toBeInTheDocument();
            expect(screen.queryByTestId("source-use-row-0")).not.toBeInTheDocument();
        });
    });

    describe("Vector 2: External link scanner in 'none' mode", () => {
        const renderControlsWithSummary = (summaryText: string) => {
            return render(
                <ManualNewsEvidenceControls
                    summary={summaryText}
                    newsUsage="none"
                    onChangeNewsUsage={() => {}}
                    sourceUses={[]}
                    onChangeSourceUses={() => {}}
                    newsArticles={sampleArticles}
                />,
            );
        };

        it("detects markdown external links in none mode", () => {
            renderControlsWithSummary("Summary citing [The Sun](https://baltimoresun.com/article/123).");
            expect(screen.getByTestId("news-usage-none-warning")).toBeInTheDocument();
        });

        it("detects bare external URLs in none mode", () => {
            renderControlsWithSummary("Summary citing bare URL http://independent.co.uk/news/story directly.");
            expect(screen.getByTestId("news-usage-none-warning")).toBeInTheDocument();
        });

        it("allows official legistar, mgaleg, congress, and localhost URLs without false positive warning", () => {
            const officialProse = [
                "Baltimore Legistar: https://baltimore.legistar.com/LegislationDetail.aspx?ID=123",
                "Legistar Subdomain: https://sub.baltimore.legistar.com/doc",
                "Maryland GA: https://mgaleg.maryland.gov/2026RS/bills/hb/hb0001f.pdf",
                "US Congress: https://congress.gov/bill/119th-congress/senate-bill/10",
                "US Congress API: https://api.congress.gov/v3/bill/119",
                "Local dev: http://localhost:3000/bills/1",
                "Local IP: http://127.0.0.1:8080/test",
            ].join("\n");

            renderControlsWithSummary(officialProse);
            expect(screen.queryByTestId("news-usage-none-warning")).not.toBeInTheDocument();
        });

        it("catches domain spoofing / lookalike URLs", () => {
            renderControlsWithSummary("Lookalike: https://fakecongress.gov/bill/1");
            expect(screen.getByTestId("news-usage-none-warning")).toBeInTheDocument();
        });

        it("catches subdomain phishing where official domain is prefix of attacker domain", () => {
            renderControlsWithSummary("Attacker: https://baltimore.legistar.com.evil-hacker.com/doc");
            expect(screen.getByTestId("news-usage-none-warning")).toBeInTheDocument();
        });

        it("ignores internal relative and anchor links without false positives", () => {
            const internalProse = "See [Section 2](#section-2) and [Related bill](/bills/42) or relative ../bills/9.";
            renderControlsWithSummary(internalProse);
            expect(screen.queryByTestId("news-usage-none-warning")).not.toBeInTheDocument();
        });

        it("ignores non-http schemes like javascript: and mailto:", () => {
            const safeProse = "Contact mailto:rep@mgaleg.maryland.gov or ignore javascript:void(0).";
            renderControlsWithSummary(safeProse);
            expect(screen.queryByTestId("news-usage-none-warning")).not.toBeInTheDocument();
        });

        it("probes mixed-case scheme handling (e.g. HTTPS://)", () => {
            renderControlsWithSummary("Summary with HTTPS://baltimoresun.com/story");
            const warningElement = screen.queryByTestId("news-usage-none-warning");
            expect(warningElement).toBeNull();
        });
    });

    describe("Vector 3: Radio switching lifecycle", () => {
        it("toggles cleanly between none and cited modes", () => {
            render(
                <StatefulControlsWrapper
                    initialSummary="Summary citing [The Sun](https://baltimoresun.com/roads)."
                    initialNewsUsage="none"
                />,
            );

            expect(screen.getByTestId("news-usage-none")).toBeChecked();
            expect(screen.getByTestId("news-usage-none-warning")).toBeInTheDocument();

            fireEvent.click(screen.getByTestId("news-usage-cited"));
            expect(screen.getByTestId("news-usage-cited")).toBeChecked();
            expect(screen.queryByTestId("news-usage-none-warning")).not.toBeInTheDocument();

            fireEvent.click(screen.getByTestId("news-usage-none"));
            expect(screen.getByTestId("news-usage-none")).toBeChecked();
            expect(screen.getByTestId("news-usage-none-warning")).toBeInTheDocument();
        });
    });

    describe("Vector 4: Text-Selection Accessibility Invariant", () => {
        // @lat: [[bill-creator-summary-tab#Why the section titles are headings rather than labels]]
        it("verifies 0 <label> tags in ManualNewsEvidenceControls", () => {
            const { container } = render(
                <ManualNewsEvidenceControls
                    summary="Some summary prose."
                    newsUsage="cited"
                    onChangeNewsUsage={() => {}}
                    sourceUses={[]}
                    onChangeSourceUses={() => {}}
                    newsArticles={sampleArticles}
                />,
            );

            const labels = container.querySelectorAll("label");
            expect(labels).toHaveLength(0);
        });

        // @lat: [[bill-creator-summary-tab#Why the section titles are headings rather than labels]]
        it("verifies 0 <label> tags in LlmSummaryEditableSummary", () => {
            const { container } = render(
                <LlmSummaryEditableSummary
                    billId={1}
                    publishedSummary="Some published summary."
                    llmDraft={null}
                    llmProvider="claude"
                    llmGeneratedAt={null}
                />,
            );

            const labels = container.querySelectorAll("label");
            expect(labels).toHaveLength(0);
        });

        it("verifies radio inputs are rendered with expected test ids and attributes", () => {
            render(
                <ManualNewsEvidenceControls
                    summary="Some summary prose."
                    newsUsage="cited"
                    onChangeNewsUsage={() => {}}
                    sourceUses={[]}
                    onChangeSourceUses={() => {}}
                    newsArticles={sampleArticles}
                />,
            );

            expect(screen.getByTestId("news-usage-none")).toHaveAttribute("type", "radio");
            expect(screen.getByTestId("news-usage-cited")).toHaveAttribute("type", "radio");
        });
    });
});
