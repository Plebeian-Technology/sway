import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import SummarySourcesLedger from "app/frontend/components/admin/creator/llm-summary/SummarySourcesLedger";
import {
    ISummarySourceDocuments,
    ISummarySourceRead,
    ISummarySourceRecord,
    ISummarySources,
} from "app/frontend/components/admin/creator/llm-summary/types";

type TReloadOptions = { only?: string[]; onFinish?: () => void };

const usePageMock = vi.fn<() => { props: Record<string, unknown> }>();
const routerReload = vi.fn<(options: TReloadOptions) => void>((options: TReloadOptions) => options.onFinish?.());

vi.mock("@inertiajs/react", () => ({
    usePage: () => usePageMock(),
    router: { reload: (options: TReloadOptions) => routerReload(options) },
}));

vi.mock("app/frontend/components/ui/button", () => ({
    Button: ({ children, onClick, ...props }: React.ButtonHTMLAttributes<HTMLButtonElement>) => (
        <button onClick={onClick} {...props}>
            {children}
        </button>
    ),
}));

vi.mock("app/frontend/components/ui/dialog", () => ({
    Dialog: ({ children, open }: { children: React.ReactNode; open?: boolean }) =>
        open ? <div>{children}</div> : null,
    DialogContent: ({ children, ...props }: React.HTMLAttributes<HTMLDivElement>) => <div {...props}>{children}</div>,
    DialogDescription: ({ children, ...props }: React.HTMLAttributes<HTMLParagraphElement>) => (
        <p {...props}>{children}</p>
    ),
    DialogFooter: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    DialogHeader: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    DialogTitle: ({ children }: { children: React.ReactNode }) => <h3>{children}</h3>,
}));

const record = (overrides: Partial<ISummarySourceRecord> = {}): ISummarySourceRecord => ({
    source_kind: "diff",
    source_chars: 568,
    source_cap: 45_000,
    source_reached_chars: 568,
    source_truncated: false,
    extracted_text_chars: 161,
    diff_target: "charter",
    diff_sections_modified: 0,
    diff_sections_referenced: 1,
    diff_sections_not_found: null,
    diff_generated_at: "2026-08-27T20:02:07Z",
    citation_keys_offered: 1,
    citation_keys_total: 1,
    citation_sample_titles: ["Approval or veto of legislation."],
    news_search_available: false,
    news_fetched_at: null,
    newsroom_domains: ["thebanner.com/baltimore", "thebanner.com/topic/politics-power", "baltimorebrew.com"],
    news_articles_offered: 0,
    news_articles_total: 0,
    news_articles: [],
    ...overrides,
});

// Bill 11's stored facts, verbatim: the only recorded run in the development corpus.
// It offers one distinct section key four times, and its facts name no newsrooms.
const BILL_11_FACTS: ISummarySourceRecord = {
    source_kind: "diff",
    source_chars: 1409,
    source_cap: 45_000,
    source_reached_chars: 1409,
    source_truncated: false,
    extracted_text_chars: 8377,
    diff_target: "code",
    diff_sections_modified: 4,
    diff_sections_referenced: 1,
    diff_sections_not_found: 0,
    diff_generated_at: "2026-09-08T12:46:10Z",
    citation_keys_offered: 4,
    citation_keys_total: 4,
    citation_sample_titles: ["Penalties.", "Penalties.", "Penalties."],
    news_search_available: false,
    news_fetched_at: "2026-09-10T13:14:57Z",
    newsroom_domains: [],
    news_articles_offered: 0,
    news_articles_total: 0,
    news_articles: [],
};

const read = (overrides: Partial<ISummarySourceRead> = {}): ISummarySourceRead => ({
    ...BILL_11_FACTS,
    built_at: "2026-07-21T17:24:50Z",
    llm_model: "claude-sonnet-4-5",
    llm_provider: "claude",
    ...overrides,
});

const sources = (overrides: Partial<ISummarySources> = {}): ISummarySources => ({
    read: null,
    now: record(),
    summary_generated_at: "2026-07-21T17:24:50Z",
    summary_model: "local",
    summary_provider: "llamacpp",
    ...overrides,
});

// The state every bill is in until a run records a snapshot: rows come from `now`.
const nowSources = (overrides: Partial<ISummarySourceRecord> = {}): ISummarySources =>
    sources({ now: record(overrides) });

const documents = (overrides: Partial<ISummarySourceDocuments> = {}): ISummarySourceDocuments => ({
    origin: "run",
    built_at: "2026-07-21T17:24:50Z",
    bill_details: "## Bill metadata\n- External ID: CB-23-0312",
    source_text: "## Bill diff (bill vs. existing law)\n+ a line the bill adds",
    citations: "## Allowed citation keys\n- charter-art-4-sec-5",
    news: "## Allowed news articles\n- https://thebanner.com/one",
    ...overrides,
});

const renderWith = (value: ISummarySources | null | undefined, docs: ISummarySourceDocuments | null = null) => {
    usePageMock.mockReturnValue({ props: { summary_sources: value, summary_source_documents: docs } });
    return render(<SummarySourcesLedger />);
};

const row = (key: string) => within(screen.getByTestId(`summary-source-${key}`));

afterEach(() => {
    cleanup();
});

beforeEach(() => {
    usePageMock.mockReset();
    routerReload.mockClear();
});

// @lat: [[bill-creator-summary-tab#Why the panel lists what the model reads]]
describe("SummarySourcesLedger", () => {
    it("renders nothing at all when the page carries no ledger", () => {
        renderWith(undefined);

        expect(screen.queryByTestId("summary-sources-ledger")).not.toBeInTheDocument();
    });

    it("heads the panel with what the model read, in the past tense", () => {
        renderWith(sources());

        expect(screen.getByRole("heading", { name: "What the model read" })).toBeInTheDocument();
    });

    it("lists the four inputs in the order the model reads them", () => {
        renderWith(sources());

        const names = screen.getAllByRole("term").map((el) => el.textContent);
        expect(names).toEqual(["Bill details", "Bill text", "Law code", "News"]);
    });

    it("says testimony and organization positions never reach the model", () => {
        renderWith(sources());

        expect(screen.getByTestId("summary-sources-exclusions")).toHaveTextContent(
            "Testimony and organization positions are not sent to the model.",
        );
    });

    it("sizes the diff file the model read, and keeps the record's section counts out of that sentence", () => {
        renderWith(sources());

        const text = row("text");
        expect(text.getByText(/The diff file, 568 characters\./)).toBeInTheDocument();
        expect(text.getByText(/\(161 characters\) is on file, but the diff takes its place\./)).toBeInTheDocument();
        expect(text.queryByText(/section referenced, none amended/)).not.toBeInTheDocument();
        expect(screen.getByTestId("summary-source-text-stamp")).toHaveTextContent("Diff record newer");
    });

    it("attributes the section counts to the stored diff record, not to the file the model read", () => {
        renderWith(
            nowSources({
                diff_target: "code",
                diff_sections_modified: 4,
                diff_sections_referenced: 1,
                diff_sections_not_found: 2,
            }),
        );

        expect(screen.getByTestId("summary-source-text-note")).toHaveTextContent(
            "The stored diff record (generated August 27, 2026) lists 4 amended sections and 1 referenced against " +
                "the City Code. 2 sections were named but not found. Those counts describe that record, not the file " +
                "the model read, which View shows.",
        );
    });

    it("carries no stamp when the summary is newer than the diff record", () => {
        renderWith(
            sources({
                now: record({ diff_sections_modified: 2, diff_sections_referenced: 3 }),
                summary_generated_at: "2026-09-01T00:00:00Z",
            }),
        );

        expect(screen.getByTestId("summary-source-text-note")).toHaveTextContent(
            "lists 2 amended sections and 3 referenced",
        );
        expect(screen.queryByTestId("summary-source-text-stamp")).not.toBeInTheDocument();
    });

    it("falls back to the bill's own text, and stamps a cut source as truncated", () => {
        renderWith(
            nowSources({
                source_kind: "extracted",
                source_chars: 61_000,
                source_reached_chars: 45_000,
                source_truncated: true,
                diff_target: null,
                diff_generated_at: null,
            }),
        );

        const text = row("text");
        expect(
            text.getByText(/The bill's own text, 61,000 characters\. No diff file exists for this bill\./),
        ).toBeInTheDocument();
        expect(text.getByText(/Only the first 45,000 characters reach the model\./)).toBeInTheDocument();
        expect(screen.getByTestId("summary-source-text-stamp")).toHaveTextContent("Truncated");
    });

    it("says plainly when there is no bill text at all", () => {
        renderWith(nowSources({ source_kind: "none", source_chars: 0, extracted_text_chars: 0 }));

        expect(row("text").getByText(/Nothing\. No bill text has been fetched/)).toBeInTheDocument();
        expect(screen.getByTestId("summary-source-text-stamp")).toHaveTextContent("No text");
    });

    it("counts citation keys with their repeats, and offers the titles as a sample", () => {
        renderWith(
            nowSources({
                citation_keys_offered: 4,
                citation_keys_total: 4,
                citation_sample_titles: ["Penalties.", "Penalties.", "Penalties."],
            }),
        );

        const law = row("law");
        expect(law.getByText(/4 citation keys the model may cite, repeats counted\./)).toBeInTheDocument();
        expect(law.getByText(/Sampled titles: Penalties\.; Penalties\.; Penalties\./)).toBeInTheDocument();
        expect(law.queryByText(/1 more/)).not.toBeInTheDocument();
    });

    it("counts the keys the allow list left out", () => {
        renderWith(nowSources({ citation_keys_offered: 250, citation_keys_total: 260, citation_sample_titles: [] }));

        expect(row("law").getByText(/10 more keys were found but left out\./)).toBeInTheDocument();
    });

    it("says when the bill names no law sections", () => {
        renderWith(nowSources({ citation_keys_offered: 0, citation_keys_total: 0, citation_sample_titles: [] }));

        expect(row("law").getByText(/found in the bill, so it can cite none\./)).toBeInTheDocument();
    });

    it("says the local model cannot search, with a neutral stamp", () => {
        renderWith(sources());

        expect(row("news").getByText(/Not searched\. The local model cannot search the web/)).toBeInTheDocument();
        expect(screen.getByTestId("summary-source-news-stamp")).toHaveTextContent("Not searched");
    });

    it("counts newsrooms by outlet, not by listed path", () => {
        renderWith(nowSources({ news_search_available: true }));

        expect(row("news").getByText("Not searched yet. The next run searches 2 newsrooms first.")).toBeInTheDocument();
    });

    it("lists the articles found by outlet and title, with the search date", () => {
        renderWith(
            nowSources({
                news_search_available: true,
                news_fetched_at: "2026-09-08T12:00:00Z",
                news_articles_offered: 2,
                news_articles_total: 2,
                news_articles: [
                    { host: "thebanner.com", title: "Council weighs conservation districts" },
                    { host: "baltimorebrew.com", title: "" },
                ],
            }),
        );

        const news = row("news");
        expect(news.getByText("2 articles from 2 newsrooms searched.")).toBeInTheDocument();
        expect(news.getByText("thebanner.com: Council weighs conservation districts")).toBeInTheDocument();
        expect(news.getByText("baltimorebrew.com")).toBeInTheDocument();
        expect(news.getByText("Searched September 08, 2026")).toBeInTheDocument();
        expect(screen.getByTestId("summary-source-news-stamp")).toHaveTextContent("Newer than summary");
    });

    it("says a search that found nothing found nothing", () => {
        renderWith(nowSources({ news_search_available: true, news_fetched_at: "2026-07-01T12:00:00Z" }));

        expect(row("news").getByText("Searched 2 newsrooms and found nothing about this bill.")).toBeInTheDocument();
        expect(screen.queryByTestId("summary-source-news-stamp")).not.toBeInTheDocument();
    });
});

// @lat: [[bill-creator-summary-tab#Why the panel lists what the model reads]]
describe("SummarySourcesLedger without a recorded run", () => {
    it("says nothing was recorded for the run that wrote the summary", () => {
        renderWith(sources());

        expect(screen.getByTestId("summary-sources-not-recorded")).toHaveTextContent(
            "Nothing was recorded for the run that wrote this summary on July 21, 2026 with local.",
        );
        expect(screen.getByTestId("summary-sources-not-recorded")).toHaveTextContent("Not recorded");
        expect(screen.queryByTestId("summary-sources-provenance")).not.toBeInTheDocument();
    });

    it("keeps a pasted summary apart from a run that left no record", () => {
        renderWith(sources({ summary_provider: "operator_paste", summary_model: null }));

        expect(screen.getByTestId("summary-sources-not-recorded")).toHaveTextContent(
            "This summary was pasted by hand on July 21, 2026, so no model read anything for it.",
        );
    });

    it("says no run has read anything when no summary exists yet", () => {
        renderWith(sources({ summary_generated_at: null, summary_model: null, summary_provider: null }));

        expect(screen.getByTestId("summary-sources-not-recorded")).toHaveTextContent(
            "No summary has been written yet, so no run has read anything.",
        );
        expect(screen.queryByTestId("summary-source-text-stamp")).not.toBeInTheDocument();
    });

    it("labels the rows as what a run would read today, not as a record", () => {
        renderWith(sources());

        expect(screen.getByTestId("summary-sources-not-recorded")).toHaveTextContent(
            "The rows below are what a run would read today, not a record of what one read.",
        );
        expect(screen.queryByTestId("summary-source-text-changed")).not.toBeInTheDocument();
    });
});

// @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
describe("SummarySourcesLedger with a recorded run", () => {
    it("names the run's date and model, and drops the not-recorded notice", () => {
        renderWith(sources({ read: read() }));

        expect(screen.getByTestId("summary-sources-provenance")).toHaveTextContent(
            "Read by claude-sonnet-4-5 on July 21, 2026.",
        );
        expect(screen.queryByTestId("summary-sources-not-recorded")).not.toBeInTheDocument();
    });

    it("renders the recorded counts rather than the ones computed now", () => {
        renderWith(sources({ read: read(), now: record({ source_chars: 61_000 }) }));

        expect(row("text").getByText(/The diff file, 1,409 characters\./)).toBeInTheDocument();
    });

    it("stamps only the rows whose inputs have moved since the run", () => {
        renderWith(
            sources({
                read: read(),
                now: { ...BILL_11_FACTS, source_chars: 61_000, diff_generated_at: "2026-09-09T12:00:00Z" },
            }),
        );

        expect(screen.getByTestId("summary-source-text-changed")).toHaveTextContent("Changed since run");
        expect(screen.queryByTestId("summary-source-law-changed")).not.toBeInTheDocument();
        expect(screen.queryByTestId("summary-source-news-changed")).not.toBeInTheDocument();
    });

    it("names the provider when the run recorded no model", () => {
        renderWith(sources({ read: read({ llm_model: null, llm_provider: "claude" }) }));

        expect(screen.getByTestId("summary-sources-provenance")).toHaveTextContent("Read by claude on July 21, 2026.");
    });
});

// @lat: [[bill-creator-summary-tab#Why each input opens a modal of its own]]
describe("SummarySourcesLedger document modals", () => {
    it("asks the server for the summary_source_documents prop by name when a row is opened", () => {
        renderWith(sources());

        fireEvent.click(screen.getByTestId("summary-source-text-view"));

        expect(routerReload).toHaveBeenCalledTimes(1);
        expect(routerReload.mock.calls[0][0].only).toEqual(["summary_source_documents"]);
    });

    it("opens one modal per row, and only the row that was asked for", () => {
        renderWith(sources(), documents());

        fireEvent.click(screen.getByTestId("summary-source-law-view"));

        expect(screen.getByTestId("summary-source-document-dialog-law")).toBeInTheDocument();
        expect(screen.queryByTestId("summary-source-document-dialog-text")).not.toBeInTheDocument();
        expect(screen.getByTestId("summary-source-document-text")).toHaveTextContent("Allowed citation keys");
    });

    it("gives each row the prompt section it was built from", () => {
        renderWith(sources(), documents());

        fireEvent.click(screen.getByTestId("summary-source-details-view"));
        expect(screen.getByTestId("summary-source-document-text")).toHaveTextContent("External ID: CB-23-0312");

        fireEvent.click(screen.getByTestId("summary-source-news-view"));
        expect(screen.getByTestId("summary-source-document-text")).toHaveTextContent("Allowed news articles");
    });

    it("keeps the text selectable, in a box that scrolls rather than one that grows", () => {
        renderWith(sources(), documents());

        fireEvent.click(screen.getByTestId("summary-source-text-view"));

        const pre = screen.getByTestId("summary-source-document-text");
        expect(pre.tagName).toBe("PRE");
        expect(pre.className).toContain("select-text");
        expect(pre.className).toContain("overflow-auto");
    });

    it("says the text was rebuilt just now when no run recorded it", () => {
        renderWith(sources(), documents({ origin: "now", built_at: null }));

        fireEvent.click(screen.getByTestId("summary-source-text-view"));

        expect(screen.getByTestId("summary-source-document-rebuilt")).toHaveTextContent(
            "No run was recorded for this bill, so this text was rebuilt just now.",
        );
    });

    it("dates the text to the run that sent it", () => {
        renderWith(sources({ read: read() }), documents());

        fireEvent.click(screen.getByTestId("summary-source-text-view"));

        expect(screen.getByTestId("summary-source-document-origin")).toHaveTextContent(
            "The text the run of July 21, 2026 sent, byte for byte.",
        );
        expect(screen.queryByTestId("summary-source-document-rebuilt")).not.toBeInTheDocument();
    });

    it("says a section the prompt never carried was not there at all", () => {
        renderWith(sources(), documents({ news: null }));

        fireEvent.click(screen.getByTestId("summary-source-news-view"));

        expect(screen.getByTestId("summary-source-document-absent")).toHaveTextContent(
            "The prompt carried no news section at all, so the model read none.",
        );
        expect(screen.queryByTestId("summary-source-document-text")).not.toBeInTheDocument();
    });

    it("tells a section that carried no text apart from one the prompt never carried", () => {
        renderWith(sources(), documents({ news: "" }));

        fireEvent.click(screen.getByTestId("summary-source-news-view"));

        expect(screen.getByTestId("summary-source-document-empty")).toHaveTextContent(
            "The prompt carried a news section with no text in it.",
        );
        expect(screen.queryByTestId("summary-source-document-absent")).not.toBeInTheDocument();
        expect(screen.queryByTestId("summary-source-document-text")).not.toBeInTheDocument();
    });

    it("shows a loading state while the text is still in flight", () => {
        routerReload.mockImplementationOnce(() => {});
        renderWith(sources(), documents());

        fireEvent.click(screen.getByTestId("summary-source-text-view"));

        expect(screen.getByTestId("summary-source-document-loading")).toBeInTheDocument();
        expect(screen.queryByTestId("summary-source-document-text")).not.toBeInTheDocument();
    });

    it("says so when the text never arrives", () => {
        renderWith(sources(), null);

        fireEvent.click(screen.getByTestId("summary-source-text-view"));

        expect(screen.getByTestId("summary-source-document-failed")).toHaveTextContent("Could not load the text.");
    });
});
