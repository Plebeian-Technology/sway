import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import * as React from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import SwayFormContext from "app/frontend/components/admin/creator/context/SwayFormContext";
import BillCreatorNewsArticles from "app/frontend/components/admin/creator/BillCreatorNewsArticles";
import type { IAdminBillNewsArticle } from "app/frontend/types/bill_creator";

interface IRouterVisitOptions {
    onSuccess?: (page: { props: Record<string, unknown> }) => void;
    onError?: (errors: unknown) => void;
    preserveScroll?: boolean;
    preserveState?: boolean;
}

const routerPost = vi.fn<(_url: string, _data?: unknown, opts?: IRouterVisitOptions) => void>();
const routerPatch = vi.fn<(_url: string, _data?: unknown, opts?: IRouterVisitOptions) => void>();
const routerReload = vi.fn<(opts?: Record<string, unknown>) => void>();
const usePageMock = vi.fn<() => Record<string, unknown>>();
const usePollMock = vi.fn<(...args: unknown[]) => void>();

vi.mock("@inertiajs/react", () => ({
    usePage: () => usePageMock(),
    usePoll: (...args: unknown[]) => usePollMock(...args),
    router: {
        post: (url: string, data?: unknown, opts?: IRouterVisitOptions) => routerPost(url, data, opts),
        patch: (url: string, data?: unknown, opts?: IRouterVisitOptions) => routerPatch(url, data, opts),
        reload: (opts?: Record<string, unknown>) => routerReload(opts),
    },
}));

const sampleArticleTextless: IAdminBillNewsArticle = {
    id: 10,
    bill_id: 42,
    news_article_id: 101,
    url: "https://thebaltimorebanner.com/community/housing-bill-123",
    title: "City Council Advances Housing Bill",
    source_name: "The Baltimore Banner",
    domain: "thebaltimorebanner.com",
    author: "Jane Reporter",
    published_at: "2026-05-18T12:00:00Z",
    approved: false,
    review_version: 0,
    stance: null,
    stance_version: 0,
    current_text_version_id: null,
    has_text: false,
    text_digest: null,
    text_origin: null,
    excerpt: null,
    created_at: "2026-05-18T12:00:00Z",
    updated_at: "2026-05-18T12:00:00Z",
    match_kind: "direct",
    article_kind: "reporting",
};

const sampleArticleWithText: IAdminBillNewsArticle = {
    id: 11,
    bill_id: 42,
    news_article_id: 102,
    url: "https://www.baltimoressun.com/opinion/editorial/housing-opinion",
    title: "Editorial: Why the Housing Bill Matters",
    source_name: "The Baltimore Sun",
    domain: "baltimoresun.com",
    author: "Editorial Board",
    published_at: "2026-05-19T09:00:00Z",
    approved: true,
    review_version: 1,
    stance: "support",
    stance_version: 1,
    current_text_version_id: 201,
    has_text: true,
    text_digest: "abcdef123456",
    text_origin: "retrieved",
    excerpt: "The council took a bold step forward today by introducing comprehensive housing reforms.",
    created_at: "2026-05-19T09:00:00Z",
    updated_at: "2026-05-19T09:00:00Z",
    match_kind: "context",
    article_kind: "editorial",
};

describe("BillCreatorNewsArticles", () => {
    beforeEach(() => {
        usePageMock.mockReturnValue({
            props: {
                bill: { id: 42 },
                news_articles: [],
            },
        });
    });

    afterEach(() => {
        cleanup();
        vi.clearAllMocks();
    });

    it("does not fetch articles or trigger discovery on mount or render", () => {
        render(<BillCreatorNewsArticles billId={42} newsArticles={[]} />);

        expect(routerPost).not.toHaveBeenCalled();
        expect(routerPatch).not.toHaveBeenCalled();
        expect(routerReload).not.toHaveBeenCalled();
        expect(usePollMock).not.toHaveBeenCalled();
    });

    it("calls router.post with explicit click on 'Fetch articles'", () => {
        render(<BillCreatorNewsArticles billId={42} newsArticles={[]} />);

        const fetchButton = screen.getByRole("button", { name: /fetch articles/i });
        fireEvent.click(fetchButton);

        expect(routerPost).toHaveBeenCalledTimes(1);
        expect(routerPost).toHaveBeenCalledWith(
            "/admin/bills/42/news_articles",
            {},
            expect.objectContaining({
                preserveScroll: true,
                preserveState: true,
            }),
        );
    });

    it("disables fetch button when no persisted bill is selected", () => {
        render(<BillCreatorNewsArticles billId={null} newsArticles={[]} />);

        const fetchButton = screen.getByRole("button", { name: /fetch articles/i });
        expect(fetchButton).toBeDisabled();
        expect(screen.getByText(/select a persisted bill to retrieve news articles/i)).toBeInTheDocument();
    });

    it("displays 'succeeded' receipt status when discovery completes with matches", async () => {
        routerPost.mockImplementation((_url, _data, opts) => {
            opts?.onSuccess?.({ props: { receipt_status: "succeeded" } });
        });

        render(<BillCreatorNewsArticles billId={42} newsArticles={[sampleArticleTextless]} />);

        const fetchButton = screen.getByRole("button", { name: /fetch articles/i });
        fireEvent.click(fetchButton);

        await waitFor(() => {
            expect(screen.getByText(/discovery completed/i)).toBeInTheDocument();
        });
    });

    it("displays informative notice for 'no_matches' status", async () => {
        routerPost.mockImplementation((_url, _data, opts) => {
            opts?.onSuccess?.({ props: { receipt_status: "no_matches" } });
        });

        render(<BillCreatorNewsArticles billId={42} newsArticles={[]} />);

        const fetchButton = screen.getByRole("button", { name: /fetch articles/i });
        fireEvent.click(fetchButton);

        await waitFor(() => {
            expect(screen.getByTestId("news-no-matches-notice")).toBeInTheDocument();
            expect(screen.getByText(/no matching articles found/i)).toBeInTheDocument();
        });
    });

    it("displays informative notice for 'unsupported' status", async () => {
        routerPost.mockImplementation((_url, _data, opts) => {
            opts?.onSuccess?.({ props: { receipt_status: "unsupported" } });
        });

        render(<BillCreatorNewsArticles billId={42} newsArticles={[]} />);

        const fetchButton = screen.getByRole("button", { name: /fetch articles/i });
        fireEvent.click(fetchButton);

        await waitFor(() => {
            expect(screen.getByTestId("news-unsupported-notice")).toBeInTheDocument();
            expect(screen.getByText(/news discovery is not supported for this provider/i)).toBeInTheDocument();
        });
    });

    it("displays error alert for 'failed' status", async () => {
        routerPost.mockImplementation((_url, _data, opts) => {
            opts?.onError?.("Upstream connection timeout");
        });

        render(<BillCreatorNewsArticles billId={42} newsArticles={[]} />);

        const fetchButton = screen.getByRole("button", { name: /fetch articles/i });
        fireEvent.click(fetchButton);

        await waitFor(() => {
            expect(screen.getByTestId("news-failed-alert")).toBeInTheDocument();
            expect(screen.getByText(/failed to fetch articles/i)).toBeInTheDocument();
            expect(screen.getByText(/Upstream connection timeout/i)).toBeInTheDocument();
        });
    });

    it("extracts news_article error string from Inertia error bag object on failure", async () => {
        routerPost.mockImplementation((_url, _data, opts) => {
            opts?.onError?.({ news_article: "Llm::TransportError: 400 bad_request_error" });
        });

        render(<BillCreatorNewsArticles billId={42} newsArticles={[]} />);

        const fetchButton = screen.getByRole("button", { name: /fetch articles/i });
        fireEvent.click(fetchButton);

        await waitFor(() => {
            expect(screen.getByTestId("news-failed-alert")).toBeInTheDocument();
            expect(screen.getByText(/Llm::TransportError: 400 bad_request_error/i)).toBeInTheDocument();
        });
    });

    it("renders candidate article card details accurately", () => {
        render(<BillCreatorNewsArticles billId={42} newsArticles={[sampleArticleTextless]} />);

        expect(screen.getByText("The Baltimore Banner")).toBeInTheDocument();
        expect(screen.getByText("thebaltimorebanner.com")).toBeInTheDocument();
        expect(screen.getByText(/by Jane Reporter/i)).toBeInTheDocument();

        const link = screen.getByRole("link", { name: /City Council Advances Housing Bill/i });
        expect(link).toHaveAttribute("href", "https://thebaltimorebanner.com/community/housing-bill-123");
        expect(link).toHaveAttribute("target", "_blank");
        expect(link).toHaveAttribute("rel", "noopener noreferrer");

        expect(screen.getByText("Direct coverage")).toBeInTheDocument();
    });

    it("displays 'Link-only' badge and warning helper for textless articles", () => {
        render(<BillCreatorNewsArticles billId={42} newsArticles={[sampleArticleTextless]} />);

        expect(screen.getByTestId("badge-link-only")).toBeInTheDocument();
        expect(screen.getByText(/link-only/i)).toBeInTheDocument();
        expect(screen.queryByTestId("badge-eligible-for-synthesis")).toBeNull();
        expect(screen.queryByTestId("article-excerpt")).toBeNull();
    });

    it("displays 'Text Available' and 'Eligible for synthesis' with excerpt for text-bearing approved articles", () => {
        render(<BillCreatorNewsArticles billId={42} newsArticles={[sampleArticleWithText]} />);

        expect(screen.getByTestId("badge-text-available")).toBeInTheDocument();
        expect(screen.getByTestId("badge-eligible-for-synthesis")).toBeInTheDocument();
        expect(screen.getByTestId("article-excerpt")).toHaveTextContent(
            "The council took a bold step forward today by introducing comprehensive housing reforms.",
        );
        expect(screen.queryByTestId("badge-link-only")).toBeNull();
    });

    it("sends router.patch with approved: true when approving an unapproved article", () => {
        render(<BillCreatorNewsArticles billId={42} newsArticles={[sampleArticleTextless]} />);

        const approveButton = screen.getByRole("button", { name: /approve for this bill/i });
        fireEvent.click(approveButton);

        expect(routerPatch).toHaveBeenCalledWith(
            "/admin/bills/42/news_articles/10",
            { approved: true },
            expect.objectContaining({
                preserveScroll: true,
                preserveState: true,
            }),
        );
        expect(routerPost).not.toHaveBeenCalled();
    });

    it("sends router.patch with approved: false when withdrawing approval", () => {
        render(<BillCreatorNewsArticles billId={42} newsArticles={[sampleArticleWithText]} />);

        const withdrawButton = screen.getByRole("button", { name: /withdraw approval/i });
        fireEvent.click(withdrawButton);

        expect(routerPatch).toHaveBeenCalledWith(
            "/admin/bills/42/news_articles/11",
            { approved: false },
            expect.objectContaining({
                preserveScroll: true,
                preserveState: true,
            }),
        );
        expect(routerPost).not.toHaveBeenCalled();
    });

    it("sends router.patch when stance selector changes", () => {
        render(<BillCreatorNewsArticles billId={42} newsArticles={[sampleArticleTextless]} />);

        const stanceSelect = screen.getByRole("combobox", { name: /opinion stance for/i });
        fireEvent.change(stanceSelect, { target: { value: "support" } });

        expect(routerPatch).toHaveBeenCalledWith(
            "/admin/bills/42/news_articles/10",
            { stance: "support" },
            expect.objectContaining({
                preserveScroll: true,
                preserveState: true,
            }),
        );
    });

    it("sends router.patch when genre selector changes", () => {
        render(<BillCreatorNewsArticles billId={42} newsArticles={[sampleArticleTextless]} />);

        const genreSelect = screen.getByRole("combobox", { name: /genre for/i });
        fireEvent.change(genreSelect, { target: { value: "op_ed" } });

        expect(routerPatch).toHaveBeenCalledWith(
            "/admin/bills/42/news_articles/10",
            { article_kind: "op_ed" },
            expect.objectContaining({
                preserveScroll: true,
                preserveState: true,
            }),
        );
    });

    it("opens manual text input, validates non-empty, and sends router.patch on save", async () => {
        render(<BillCreatorNewsArticles billId={42} newsArticles={[sampleArticleTextless]} />);

        const addTextButton = screen.getByRole("button", { name: /add text for article 10/i });
        fireEvent.click(addTextButton);

        const textarea = screen.getByRole("textbox", { name: /manual article text/i });
        expect(textarea).toBeInTheDocument();

        const saveButton = screen.getByRole("button", { name: /save article text/i });
        fireEvent.click(saveButton);
        expect(routerPatch).not.toHaveBeenCalled();

        fireEvent.change(textarea, { target: { value: "This is verified manual text for testing." } });
        fireEvent.click(saveButton);

        expect(routerPatch).toHaveBeenCalledWith(
            "/admin/bills/42/news_articles/10",
            { text: "This is verified manual text for testing." },
            expect.objectContaining({
                preserveScroll: true,
                preserveState: true,
            }),
        );
    });

    it("preserves unsaved form draft in SwayFormContext across review operations", () => {
        const setDataMock = vi.fn<(...args: unknown[]) => void>();
        const fakeFormContext = {
            data: { summary: "Unsaved local operator draft summary", title: "Original Title" },
            setData: setDataMock,
            errors: {},
        } as unknown as React.ContextType<typeof SwayFormContext>;

        render(
            <SwayFormContext.Provider value={fakeFormContext}>
                <BillCreatorNewsArticles billId={42} newsArticles={[sampleArticleTextless]} />
            </SwayFormContext.Provider>,
        );

        const approveButton = screen.getByRole("button", { name: /approve for this bill/i });
        fireEvent.click(approveButton);

        expect(setDataMock).not.toHaveBeenCalled();
        expect(fakeFormContext?.data.summary).toBe("Unsaved local operator draft summary");
    });

    it("uses semantic theme tokens for badges, alerts, and controls instead of raw palette classes or border-input", () => {
        const { container } = render(
            <BillCreatorNewsArticles billId={42} newsArticles={[sampleArticleTextless, sampleArticleWithText]} />,
        );

        fireEvent.click(screen.getByRole("button", { name: /add text for article 10/i }));

        expect(screen.getByTestId("badge-approved-11").className).toContain("text-success");
        expect(screen.getByTestId("badge-unapproved-10").className).toContain("text-foreground");
        expect(screen.getByTestId("badge-text-available").className).toContain("text-info");
        expect(screen.getByTestId("badge-eligible-for-synthesis").className).toContain("text-success");
        expect(screen.getByTestId("badge-link-only").className).toContain("text-warning");

        const html = container.innerHTML;
        expect(html).not.toMatch(/\bdark:/);
        expect(html).not.toMatch(/\b(text|bg|border)-(green|amber|blue|emerald)-/);
        expect(html).not.toContain("border-input");
    });

    it("renders inert text without an anchor for unsafe or file:/// article URLs", () => {
        const fileArticle: IAdminBillNewsArticle = {
            ...sampleArticleTextless,
            id: 99,
            title: "Local File Leak Attempt",
            url: "file:///etc/passwd",
        };
        const emptyUrlArticle: IAdminBillNewsArticle = {
            ...sampleArticleTextless,
            id: 100,
            title: "Empty URL Article",
            url: "",
        };

        const { container } = render(
            <BillCreatorNewsArticles billId={42} newsArticles={[fileArticle, emptyUrlArticle]} />,
        );

        expect(screen.queryByRole("link", { name: /Local File Leak Attempt/i })).toBeNull();
        expect(screen.queryByRole("link", { name: /Empty URL Article/i })).toBeNull();
        expect(screen.getByText("Local File Leak Attempt")).toBeInTheDocument();
        expect(screen.getByText("Empty URL Article")).toBeInTheDocument();
        expect(container.querySelectorAll("a")).toHaveLength(0);
    });
});
