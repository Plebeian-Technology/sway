import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

const mockApiGet = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: { get: (...args: unknown[]) => mockApiGet(...args) },
}));

import SummarySourcesSection from "../../../../src/components/admin/billCreator/SummarySourcesSection";

const record = (overrides: Record<string, unknown> = {}) => ({
    source_kind: "extracted",
    source_chars: 12000,
    source_cap: 300000,
    source_reached_chars: 12000,
    source_truncated: false,
    extracted_text_chars: 12000,
    diff_target: null,
    diff_sections_modified: null,
    diff_sections_referenced: null,
    diff_sections_not_found: null,
    diff_generated_at: null,
    citation_keys_offered: 0,
    citation_keys_total: 0,
    citation_sample_titles: [],
    news_search_available: true,
    news_fetched_at: null,
    newsroom_domains: [],
    news_articles_offered: 0,
    news_articles_total: 0,
    news_articles: [],
    ...overrides,
});

const sources = (overrides: Record<string, unknown> = {}) => ({
    read: null,
    now: record(),
    summary_generated_at: "2026-11-01T15:30:00Z",
    summary_model: "sonnet",
    summary_provider: "claude",
    ...overrides,
});

const READ = {
    ...record({ source_chars: 9000 }),
    built_at: "2026-11-02T12:00:00Z",
    llm_model: "sonnet",
    llm_provider: "claude",
};

const documents = (overrides: Record<string, unknown> = {}) => ({
    origin: "run",
    built_at: "2026-11-02T12:00:00Z",
    bill_details: "## Bill metadata",
    source_text: "## Bill text\n\nSection A.",
    citations: "",
    news: null,
    ...overrides,
});

const renderSection = (summarySources: unknown, billId: number | null = 42) =>
    render(<SummarySourcesSection billId={billId} data={{ summary_sources: summarySources }} refresh={jest.fn()} />);

// @lat: [[mobile-bill-creator#Sections#The summary sources section]]
describe("SummarySourcesSection", () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    it("shows an empty state when the server sent no sources", () => {
        renderSection(undefined);

        expect(screen.getByTestId("admin-summary-sources-empty")).toBeTruthy();
        expect(screen.queryByTestId("admin-summary-source-text")).toBeNull();
    });

    it("asks to save the bill first when there is none", () => {
        renderSection(undefined, null);

        expect(screen.getByText("Save this bill to see what the model read.")).toBeTruthy();
    });

    it("renders the four rows from the sources the server sent", () => {
        renderSection(sources());

        expect(screen.getByTestId("admin-summary-source-details")).toBeTruthy();
        expect(screen.getByTestId("admin-summary-source-text")).toBeTruthy();
        expect(screen.getByTestId("admin-summary-source-law")).toBeTruthy();
        expect(screen.getByTestId("admin-summary-source-news")).toBeTruthy();
        expect(screen.getByText("Its number, title, status and release date.")).toBeTruthy();
        expect(screen.getByText(/The bill's own text, 12,000 characters\. No diff file exists/)).toBeTruthy();
        expect(screen.getByText(/No sections of existing law were found/)).toBeTruthy();
        expect(screen.getByText(/No newsrooms are set up for this jurisdiction/)).toBeTruthy();
        expect(screen.getByTestId("admin-summary-sources-exclusions")).toBeTruthy();
    });

    it("says nothing was recorded and what a run would read today when no run was recorded", () => {
        renderSection(sources());

        expect(screen.getByTestId("admin-summary-sources-not-recorded")).toBeTruthy();
        expect(
            screen.getByText(
                "Nothing was recorded for the run that wrote this summary on November 1, 2026 with sonnet.",
            ),
        ).toBeTruthy();
        expect(screen.getByText(/what a run would read today, not a record of what one read/)).toBeTruthy();
    });

    it("says no model read anything for a pasted summary", () => {
        renderSection(sources({ summary_provider: "operator_paste", summary_model: null }));

        expect(screen.getByText(/pasted by hand on November 1, 2026, so no model read anything/)).toBeTruthy();
    });

    it("says no run has read anything before a summary exists", () => {
        renderSection(sources({ summary_generated_at: null }));

        expect(screen.getByText("No summary has been written yet, so no run has read anything.")).toBeTruthy();
    });

    it("shows the recorded run and flags a row that changed since it", () => {
        renderSection(sources({ read: READ }));

        expect(screen.queryByTestId("admin-summary-sources-not-recorded")).toBeNull();
        expect(screen.getByText("Read by sonnet on November 2, 2026.")).toBeTruthy();
        expect(screen.getByText(/The bill's own text, 9,000 characters/)).toBeTruthy();
        expect(screen.getByTestId("admin-summary-source-text-changed")).toBeTruthy();
        expect(screen.queryByTestId("admin-summary-source-law-changed")).toBeNull();
    });

    it("names the diff file, the stored record and a truncated text", () => {
        renderSection(
            sources({
                now: record({
                    source_kind: "diff",
                    source_chars: 5000,
                    source_truncated: true,
                    source_cap: 4000,
                    diff_target: "charter",
                    diff_sections_modified: 1,
                    diff_sections_referenced: 12,
                    diff_sections_not_found: 2,
                    diff_generated_at: "2026-11-03T10:00:00Z",
                }),
            }),
        );

        expect(
            screen.getByText(
                "The diff file, 5,000 characters. The bill's own text (12,000 characters) is on file, but the diff takes its place. Only the first 4,000 characters reach the model.",
            ),
        ).toBeTruthy();
        expect(screen.getByText("Truncated")).toBeTruthy();
        expect(
            screen.getByText(
                "The stored diff record (generated November 3, 2026) lists 1 amended section and 12 referenced against the City Charter. 2 sections were named but not found. Those counts describe that record, not the file the model read, which View shows.",
            ),
        ).toBeTruthy();
    });

    it("says no text was fetched", () => {
        renderSection(sources({ now: record({ source_kind: "none", source_chars: 0 }) }));

        expect(screen.getByText(/Nothing\. No bill text has been fetched/)).toBeTruthy();
        expect(screen.getByText("No text")).toBeTruthy();
    });

    it("describes the law keys offered, sampled and left out", () => {
        renderSection(
            sources({
                now: record({
                    citation_keys_offered: 3,
                    citation_keys_total: 5,
                    citation_sample_titles: ["Art. 1", "Art. 2"],
                }),
            }),
        );

        expect(
            screen.getByText(
                "3 citation keys the model may cite, repeats counted. Sampled titles: Art. 1; Art. 2. 2 more keys were found but left out.",
            ),
        ).toBeTruthy();
    });

    it("says none of the found law could be offered", () => {
        renderSection(sources({ now: record({ citation_keys_offered: 0, citation_keys_total: 4 }) }));

        expect(screen.getByText("4 sections were found, but none could be offered to cite.")).toBeTruthy();
    });

    it("lists the news articles and stamps a search newer than the summary", () => {
        renderSection(
            sources({
                now: record({
                    newsroom_domains: ["a.com/rss", "a.com/feed", "b.com"],
                    news_fetched_at: "2026-11-05T09:00:00Z",
                    news_articles_offered: 2,
                    news_articles: [
                        { title: "Council votes", host: "a.com" },
                        { title: "", host: "b.com" },
                    ],
                }),
            }),
        );

        expect(screen.getByText("2 articles from 2 newsrooms searched.")).toBeTruthy();
        expect(screen.getByText("• a.com: Council votes")).toBeTruthy();
        expect(screen.getByText("• b.com")).toBeTruthy();
        expect(screen.getByText("Searched November 5, 2026")).toBeTruthy();
        expect(screen.getByText("Newer than summary")).toBeTruthy();
    });

    it("says a local model could not search", () => {
        renderSection(sources({ now: record({ newsroom_domains: ["a.com"], news_search_available: false }) }));

        expect(screen.getByText(/Not searched\. The local model cannot search the web/)).toBeTruthy();
        expect(screen.getByText("Not searched")).toBeTruthy();
    });

    it("says the next run searches the newsrooms first", () => {
        renderSection(sources({ now: record({ newsroom_domains: ["a.com"] }) }));

        expect(screen.getByText("Not searched yet. The next run searches 1 newsroom first.")).toBeTruthy();
    });

    it("says a search found nothing", () => {
        renderSection(
            sources({
                now: record({
                    newsroom_domains: ["a.com"],
                    news_fetched_at: "2026-10-01T09:00:00Z",
                    news_articles_offered: 0,
                }),
            }),
        );

        expect(screen.getByText("Searched 1 newsroom and found nothing about this bill.")).toBeTruthy();
    });

    describe("viewing what the model was given", () => {
        it("asks for the documents on the summary address and shows the row's text", async () => {
            mockApiGet.mockResolvedValue({ summary_source_documents: documents() });
            renderSection(sources());

            fireEvent.press(screen.getByTestId("admin-summary-source-text-view"));

            expect(await screen.findByTestId("admin-summary-source-text-document-text")).toBeTruthy();
            expect(screen.getByText(/## Bill text/)).toBeTruthy();
            expect(mockApiGet).toHaveBeenCalledWith("/admin/bill_creator/42/summary?summary_source_documents=1");
            expect(screen.getByText("The text the run of November 2, 2026 sent, byte for byte.")).toBeTruthy();
        });

        it("shows a loading line until the answer arrives", async () => {
            mockApiGet.mockReturnValue(new Promise(() => {}));
            renderSection(sources());

            fireEvent.press(screen.getByTestId("admin-summary-source-text-view"));

            expect(await screen.findByTestId("admin-summary-source-text-document-loading")).toBeTruthy();
        });

        it("says the text could not be loaded", async () => {
            mockApiGet.mockRejectedValue(new Error("boom"));
            renderSection(sources());

            fireEvent.press(screen.getByTestId("admin-summary-source-text-view"));

            expect(await screen.findByTestId("admin-summary-source-text-document-failed")).toBeTruthy();
        });

        it("marks text rebuilt just now when no run was recorded", async () => {
            mockApiGet.mockResolvedValue({ summary_source_documents: documents({ origin: "now", built_at: null }) });
            renderSection(sources());

            fireEvent.press(screen.getByTestId("admin-summary-source-text-view"));

            expect(await screen.findByTestId("admin-summary-source-text-document-rebuilt")).toBeTruthy();
            expect(screen.getByText("Rebuilt just now from the bill as it stands.")).toBeTruthy();
        });

        it("tells an absent section from an empty one", async () => {
            mockApiGet.mockResolvedValue({ summary_source_documents: documents() });
            renderSection(sources());

            fireEvent.press(screen.getByTestId("admin-summary-source-news-view"));
            expect(await screen.findByTestId("admin-summary-source-news-document-absent")).toBeTruthy();

            fireEvent.press(screen.getByTestId("admin-summary-source-law-view"));
            expect(await screen.findByTestId("admin-summary-source-law-document-empty")).toBeTruthy();
        });

        it("asks again on every open and hides the text on a second press", async () => {
            mockApiGet.mockResolvedValue({ summary_source_documents: documents() });
            renderSection(sources());

            fireEvent.press(screen.getByTestId("admin-summary-source-text-view"));
            await screen.findByTestId("admin-summary-source-text-document-text");
            fireEvent.press(screen.getByTestId("admin-summary-source-text-view"));
            expect(screen.queryByTestId("admin-summary-source-text-document")).toBeNull();

            fireEvent.press(screen.getByTestId("admin-summary-source-text-view"));
            await waitFor(() => expect(mockApiGet).toHaveBeenCalledTimes(2));
        });
    });
});
