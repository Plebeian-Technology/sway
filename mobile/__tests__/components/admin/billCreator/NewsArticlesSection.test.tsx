import React from "react";
import { Linking } from "react-native";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError, NetworkError } from "../../../../src/api/errors";

const mockApiPost = jest.fn();
const mockApiPatch = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: {
        post: (...args: unknown[]) => mockApiPost(...args),
        patch: (...args: unknown[]) => mockApiPatch(...args),
        get: jest.fn(),
    },
}));

jest.mock("../../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

import NewsArticlesSection from "../../../../src/components/admin/billCreator/NewsArticlesSection";
import SummaryTab from "../../../../src/screens/admin/billCreator/tabs/SummaryTab";

const article = (overrides: Record<string, unknown> = {}) => ({
    id: 7,
    bill_id: 42,
    news_article_id: 3,
    approved: false,
    review_version: 0,
    stance: null,
    stance_version: 0,
    current_text_version_id: null,
    match_kind: "direct",
    article_kind: "reporting",
    url: "https://www.thebanner.com/politics/bill-25-0001",
    title: "Council weighs the fee",
    source_name: "The Baltimore Banner",
    domain: "thebanner.com",
    author: "Jane Reporter",
    published_at: "2026-11-02T15:00:00Z",
    has_text: false,
    text_digest: null,
    text_origin: null,
    excerpt: null,
    created_at: "2026-11-03T12:00:00Z",
    updated_at: "2026-11-03T12:00:00Z",
    ...overrides,
});

const tabData = (extra: Record<string, unknown> = {}) => ({
    bill: { id: 42, external_id: "25-0001", title: "A bill" },
    news_articles: [],
    receipt_status: null,
    ...extra,
});

const renderSection = (data: ReturnType<typeof tabData>, billId: number | null = 42) => {
    const refresh = jest.fn(async () => {});
    const view = render(<NewsArticlesSection billId={billId} data={data} refresh={refresh} />);
    return { refresh, rerender: view.rerender };
};

// @lat: [[mobile-bill-creator#Sections#The news articles section]]
describe("NewsArticlesSection", () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    it("renders under the Summary tab", () => {
        render(<SummaryTab billId={42} data={tabData()} refresh={jest.fn(async () => {})} />);

        expect(screen.getByTestId("admin-news-articles")).toBeTruthy();
    });

    it("says no articles were retrieved before any discovery", () => {
        renderSection(tabData());

        expect(screen.getByTestId("admin-news-articles-empty")).toHaveTextContent(
            'No news articles retrieved yet. Tap "Fetch articles" to search configured newsrooms.',
        );
        expect(screen.getByTestId("admin-news-articles-fetch")).toHaveTextContent("Fetch articles");
    });

    it("asks to save a new bill and keeps Fetch articles disabled", () => {
        renderSection(tabData(), null);

        expect(screen.getByTestId("admin-news-articles-unsaved")).toHaveTextContent(
            "Save this bill to retrieve news articles.",
        );
        expect(screen.getByTestId("admin-news-articles-fetch")).toBeDisabled();
    });

    it("renders each article with its outlet, badges, byline and text state", () => {
        renderSection(
            tabData({
                news_articles: [
                    article(),
                    article({
                        id: 8,
                        match_kind: "context",
                        approved: true,
                        has_text: true,
                        text_origin: "fetched",
                        excerpt: "The council voted to raise the fee.",
                        title: null,
                        source_name: null,
                        domain: null,
                        author: null,
                        published_at: null,
                    }),
                ],
            }),
        );

        const linkOnly = screen.getByTestId("admin-news-article-7");
        expect(linkOnly).toHaveTextContent(/The Baltimore Banner/);
        expect(linkOnly).toHaveTextContent(/thebanner\.com/);
        expect(linkOnly).toHaveTextContent(/Direct coverage/);
        expect(linkOnly).toHaveTextContent(/Unapproved candidate/);
        expect(linkOnly).toHaveTextContent(/Council weighs the fee/);
        expect(linkOnly).toHaveTextContent(/by Jane Reporter/);
        expect(linkOnly).toHaveTextContent(/Nov 2, 2026/);
        expect(screen.getByTestId("admin-news-article-7-link-only")).toHaveTextContent(
            /Link-only.*Cannot be cited in summary synthesis until text is provided\./,
        );
        expect(screen.queryByTestId("admin-news-article-7-excerpt")).toBeNull();

        const withText = screen.getByTestId("admin-news-article-8");
        expect(withText).toHaveTextContent(/Unknown outlet/);
        expect(withText).toHaveTextContent(/Issue context/);
        expect(withText).toHaveTextContent(/Approved/);
        expect(withText).toHaveTextContent(/Untitled article/);
        expect(screen.getByTestId("admin-news-article-8-text")).toHaveTextContent(
            /Text Available.*Eligible for synthesis.*Origin: fetched/,
        );
        expect(screen.getByTestId("admin-news-article-8-excerpt")).toHaveTextContent(
            "The council voted to raise the fee.",
        );
        expect(screen.queryByTestId("admin-news-articles-empty")).toBeNull();
    });

    it("opens a safe article address and shows an unsafe one as plain text", () => {
        const openURL = jest.spyOn(Linking, "openURL").mockResolvedValue(undefined);
        renderSection(
            tabData({
                news_articles: [article(), article({ id: 9, url: "javascript:alert(1)", title: "Bad link" })],
            }),
        );

        fireEvent.press(screen.getByTestId("admin-news-article-7-link"));
        expect(openURL).toHaveBeenCalledWith("https://www.thebanner.com/politics/bill-25-0001");
        expect(screen.queryByTestId("admin-news-article-9-link")).toBeNull();
        expect(screen.getByTestId("admin-news-article-9")).toHaveTextContent(/Bad link/);
        openURL.mockRestore();
    });

    it.each([
        ["succeeded", "admin-news-succeeded", "Discovery completed successfully."],
        [
            "no_matches",
            "admin-news-no-matches",
            "No matching articles found for this bill in configured newsroom sources.",
        ],
        ["unsupported", "admin-news-unsupported", "News discovery is not supported for this provider or locale."],
        ["failed", "admin-news-failed", "Failed to fetch articles from news sources."],
    ])("shows the %s notice from the loaded receipt status", (status, testID, text) => {
        renderSection(tabData({ receipt_status: status }));

        expect(screen.getByTestId(testID)).toHaveTextContent(text);
        expect(screen.queryByTestId("admin-news-articles-empty")).toBeNull();
    });

    it("posts a discovery and shows the articles and status it answers", async () => {
        let resolve: (value: unknown) => void = () => {};
        mockApiPost.mockReturnValue(
            new Promise((res) => {
                resolve = res;
            }),
        );
        renderSection(tabData({ receipt_status: "no_matches" }));

        fireEvent.press(screen.getByTestId("admin-news-articles-fetch"));

        expect(mockApiPost).toHaveBeenCalledWith("/admin/bills/42/news_articles", {});
        expect(screen.getByTestId("admin-news-articles-fetch")).toHaveTextContent("Fetching articles...");
        expect(screen.getByTestId("admin-news-articles-fetch")).toBeDisabled();
        expect(screen.queryByTestId("admin-news-no-matches")).toBeNull();

        await act(async () => {
            resolve({ receipt_status: "succeeded", articles: [article()] });
        });

        expect(screen.getByTestId("admin-news-succeeded")).toBeTruthy();
        expect(screen.getByTestId("admin-news-article-7")).toBeTruthy();
        expect(screen.getByTestId("admin-news-articles-fetch")).toHaveTextContent("Fetch articles");
    });

    describe("while a discovery is in flight", () => {
        beforeEach(() => {
            jest.useFakeTimers();
        });

        afterEach(() => {
            jest.useRealTimers();
        });

        // @lat: [[mobile-bill-creator#Sections#The news articles section#Polling while a discovery runs]]
        it("refetches the tab every five seconds until the receipt settles", async () => {
            mockApiPost.mockResolvedValue({ receipt_status: "running", articles: [] });
            const { refresh, rerender } = renderSection(tabData());

            fireEvent.press(screen.getByTestId("admin-news-articles-fetch"));
            await waitFor(() => expect(mockApiPost).toHaveBeenCalledTimes(1));
            await act(async () => {});

            expect(refresh).not.toHaveBeenCalled();
            act(() => {
                jest.advanceTimersByTime(5000);
            });
            expect(refresh).toHaveBeenCalledTimes(1);

            rerender(
                <NewsArticlesSection
                    billId={42}
                    data={tabData({ receipt_status: "succeeded", news_articles: [article()] })}
                    refresh={refresh}
                />,
            );
            expect(screen.getByTestId("admin-news-succeeded")).toBeTruthy();
            expect(screen.getByTestId("admin-news-article-7")).toBeTruthy();
            act(() => {
                jest.advanceTimersByTime(20000);
            });
            expect(refresh).toHaveBeenCalledTimes(1);
        });

        it("polls when the tab loads with a queued receipt", () => {
            const { refresh } = renderSection(tabData({ receipt_status: "queued" }));

            act(() => {
                jest.advanceTimersByTime(5000);
            });
            expect(refresh).toHaveBeenCalledTimes(1);
        });
    });

    // @lat: [[mobile-bill-creator#Sections#The news articles section#A refused discovery]]
    it("shows a refused discovery from the 422 body", async () => {
        mockApiPost.mockRejectedValue(
            new ApiRequestError("http_422", "Something went wrong. Please try again.", undefined, 422, {
                receipt_status: "failed",
                articles: [article()],
            }),
        );
        renderSection(tabData());

        fireEvent.press(screen.getByTestId("admin-news-articles-fetch"));

        await waitFor(() =>
            expect(screen.getByTestId("admin-news-failed")).toHaveTextContent(
                "Failed to fetch articles from news sources.",
            ),
        );
        expect(screen.getByTestId("admin-news-failed")).not.toHaveTextContent(/Something went wrong/);
        expect(screen.getByTestId("admin-news-article-7")).toBeTruthy();
        expect(screen.queryByTestId("admin-news-articles-empty")).toBeNull();
    });

    it("names a refused discovery's reason in brackets", async () => {
        mockApiPost.mockRejectedValue(
            new ApiRequestError("http_422", "Connection refused: provider timeout", undefined, 422, {
                receipt_status: "failed",
                articles: [],
                error: "Connection refused: provider timeout",
            }),
        );
        renderSection(tabData());

        fireEvent.press(screen.getByTestId("admin-news-articles-fetch"));

        await waitFor(() =>
            expect(screen.getByTestId("admin-news-failed")).toHaveTextContent(
                "Failed to fetch articles from news sources. (Connection refused: provider timeout)",
            ),
        );
    });

    it("shows the error message when the request fails without a receipt", async () => {
        mockApiPost.mockRejectedValue(new NetworkError("network_error", "Network request failed"));
        renderSection(tabData());

        fireEvent.press(screen.getByTestId("admin-news-articles-fetch"));

        await waitFor(() =>
            expect(screen.getByTestId("admin-news-failed")).toHaveTextContent(
                "Failed to fetch articles from news sources. (Network request failed)",
            ),
        );
    });

    // @lat: [[mobile-bill-creator#Sections#The news articles section#Reviewing an article]]
    describe("reviewing an article", () => {
        const articlePath = "/admin/bills/42/news_articles/7";

        it.each([
            [false, "Approve for this bill", { approved: true }],
            [true, "Withdraw approval", { approved: false }],
        ])("sends the approval toggle for an article approved=%s", async (approved, label, body) => {
            mockApiPatch.mockResolvedValue(article({ approved: !approved }));
            const { refresh } = renderSection(tabData({ news_articles: [article({ approved })] }));

            expect(screen.getByTestId("admin-news-article-7-approve")).toHaveTextContent(label);
            fireEvent.press(screen.getByTestId("admin-news-article-7-approve"));

            await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
            expect(mockApiPatch).toHaveBeenCalledWith(articlePath, body);
        });

        it("sends a new genre and marks the current one selected", async () => {
            mockApiPatch.mockResolvedValue(article({ article_kind: "op_ed" }));
            const { refresh } = renderSection(tabData({ news_articles: [article({ article_kind: null })] }));

            expect(screen.getByTestId("admin-news-article-7-genre-reporting")).toBeSelected();
            fireEvent.press(screen.getByTestId("admin-news-article-7-genre-reporting"));
            expect(mockApiPatch).not.toHaveBeenCalled();

            fireEvent.press(screen.getByTestId("admin-news-article-7-genre-op_ed"));

            await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
            expect(mockApiPatch).toHaveBeenCalledWith(articlePath, { article_kind: "op_ed" });
        });

        it.each([
            [null, "support", { stance: "support" }],
            ["support", "none", { stance: "" }],
        ])("sends the stance change from %s to %s", async (stance, option, body) => {
            mockApiPatch.mockResolvedValue(article());
            const { refresh } = renderSection(tabData({ news_articles: [article({ stance })] }));

            fireEvent.press(screen.getByTestId(`admin-news-article-7-stance-${option}`));

            await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
            expect(mockApiPatch).toHaveBeenCalledWith(articlePath, body);
        });

        it("refuses blank manual text and sends trimmed text", async () => {
            mockApiPatch.mockResolvedValue(article({ has_text: true }));
            const { refresh } = renderSection(tabData({ news_articles: [article()] }));

            expect(screen.queryByTestId("admin-news-article-7-manual-text")).toBeNull();
            fireEvent.press(screen.getByTestId("admin-news-article-7-edit-text"));
            fireEvent.changeText(screen.getByTestId("admin-news-article-7-manual-text"), "   ");
            fireEvent.press(screen.getByTestId("admin-news-article-7-save-text"));

            expect(screen.getByTestId("admin-news-article-7-manual-text-error")).toHaveTextContent(
                "Article text cannot be blank.",
            );
            expect(mockApiPatch).not.toHaveBeenCalled();

            fireEvent.changeText(screen.getByTestId("admin-news-article-7-manual-text"), "  The full story.  ");
            fireEvent.press(screen.getByTestId("admin-news-article-7-save-text"));

            await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
            expect(mockApiPatch).toHaveBeenCalledWith(articlePath, { text: "The full story." });
            expect(screen.queryByTestId("admin-news-article-7-manual-text")).toBeNull();
        });

        it("labels the text button by whether the article has text, and cancels the editor", () => {
            renderSection(tabData({ news_articles: [article({ has_text: true })] }));

            expect(screen.getByTestId("admin-news-article-7-edit-text")).toHaveTextContent("Replace text");
            fireEvent.press(screen.getByTestId("admin-news-article-7-edit-text"));
            expect(screen.getByTestId("admin-news-article-7-edit-text")).toHaveTextContent("Cancel");
            fireEvent.press(screen.getByTestId("admin-news-article-7-edit-text"));
            expect(screen.queryByTestId("admin-news-article-7-manual-text")).toBeNull();
        });

        it("disables the article's controls while its update runs", () => {
            mockApiPatch.mockReturnValue(new Promise(() => {}));
            renderSection(tabData({ news_articles: [article()] }));

            fireEvent.press(screen.getByTestId("admin-news-article-7-approve"));

            expect(screen.getByTestId("admin-news-article-7-approve")).toBeDisabled();
            expect(screen.getByTestId("admin-news-article-7-genre-op_ed")).toBeDisabled();
            expect(screen.getByTestId("admin-news-article-7-stance-support")).toBeDisabled();
            expect(screen.getByTestId("admin-news-article-7-edit-text")).toBeDisabled();
        });

        it("shows a refused update's message and keeps the tab data", async () => {
            mockApiPatch.mockRejectedValue(
                new ApiRequestError("http_422", "Invalid stance: maybe", undefined, 422, {
                    error: "Invalid stance: maybe",
                }),
            );
            const { refresh } = renderSection(tabData({ news_articles: [article()] }));

            fireEvent.press(screen.getByTestId("admin-news-article-7-stance-oppose"));

            await waitFor(() =>
                expect(screen.getByTestId("admin-news-article-7-review-error")).toHaveTextContent(
                    "Invalid stance: maybe",
                ),
            );
            expect(refresh).not.toHaveBeenCalled();
        });

        it("shows the reloaded articles after reviewing one a refused discovery listed", async () => {
            mockApiPost.mockRejectedValue(
                new ApiRequestError("http_422", "Something went wrong. Please try again.", undefined, 422, {
                    receipt_status: "failed",
                    articles: [article()],
                }),
            );
            mockApiPatch.mockResolvedValue(article({ approved: true }));
            const { refresh, rerender } = renderSection(tabData());

            fireEvent.press(screen.getByTestId("admin-news-articles-fetch"));
            await waitFor(() => expect(screen.getByTestId("admin-news-article-7")).toBeTruthy());
            fireEvent.press(screen.getByTestId("admin-news-article-7-approve"));
            await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));

            rerender(
                <NewsArticlesSection
                    billId={42}
                    data={tabData({ receipt_status: "failed", news_articles: [article({ approved: true })] })}
                    refresh={refresh}
                />,
            );

            expect(screen.getByTestId("admin-news-article-7")).toHaveTextContent(/Approved/);
            expect(screen.getByTestId("admin-news-article-7")).not.toHaveTextContent(/Unapproved candidate/);
            expect(screen.getByTestId("admin-news-failed")).toBeTruthy();
        });

        it("leaves out review controls for an unsaved bill", () => {
            renderSection(tabData({ news_articles: [article()] }), null);

            expect(screen.queryByTestId("admin-news-article-7-approve")).toBeNull();
        });
    });
});
