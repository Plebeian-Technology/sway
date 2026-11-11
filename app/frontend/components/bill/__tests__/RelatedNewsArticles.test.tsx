import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import type { sway } from "sway";

import RelatedNewsArticles from "app/frontend/components/bill/RelatedNewsArticles";

afterEach(cleanup);

describe("RelatedNewsArticles", () => {
    describe("empty and nil states", () => {
        it("renders null (0 DOM nodes) when articles prop is undefined", () => {
            const { container } = render(<RelatedNewsArticles articles={undefined} />);
            expect(container.firstChild).toBeNull();
            expect(container.innerHTML).toBe("");
        });

        it("renders null (0 DOM nodes) when articles prop is null", () => {
            const { container } = render(<RelatedNewsArticles articles={null as unknown as sway.INewsArticle[]} />);
            expect(container.firstChild).toBeNull();
            expect(container.innerHTML).toBe("");
        });

        it("renders null (0 DOM nodes) when articles prop is an empty array", () => {
            const { container } = render(<RelatedNewsArticles articles={[]} />);
            expect(container.firstChild).toBeNull();
            expect(container.innerHTML).toBe("");
        });
    });

    describe("core article presentation", () => {
        const article: sway.INewsArticle = {
            id: 10,
            title: "Transit Overhaul Advances to City Council",
            url: "https://www.baltimoresun.com/news/transit-bill-2026",
            outlet_name: "The Baltimore Sun",
            author_name: "Emily Vance",
            published_at: "2026-04-12T14:30:00Z",
            article_kind: "reporting",
            match_kind: "direct",
        };

        it("renders article title, outlet name, publication date, and author byline", () => {
            render(<RelatedNewsArticles articles={[article]} />);

            const link = screen.getByRole("link", { name: /Transit Overhaul Advances to City Council/i });
            expect(link).toBeInTheDocument();
            expect(link).toHaveAttribute("href", "https://www.baltimoresun.com/news/transit-bill-2026");
            expect(screen.getByText("The Baltimore Sun")).toBeInTheDocument();
            expect(screen.getByText(/April 12, 2026/)).toBeInTheDocument();
            expect(screen.getByText(/Emily Vance/)).toBeInTheDocument();
        });

        it("renders external link with target='_blank' and rel='noopener noreferrer'", () => {
            render(<RelatedNewsArticles articles={[article]} />);

            const link = screen.getByRole("link", { name: /Transit Overhaul Advances to City Council/i });
            expect(link).toHaveAttribute("target", "_blank");
            expect(link).toHaveAttribute("rel", "noopener noreferrer");
        });

        it("provides accessible screen reader hint for external link", () => {
            render(<RelatedNewsArticles articles={[article]} />);

            expect(screen.getByText(/\(opens in new tab\)/i)).toBeInTheDocument();
        });
    });

    describe("URL scheme security & validation", () => {
        it("allows https: and http: external links", () => {
            const articles: sway.INewsArticle[] = [
                {
                    id: 1,
                    title: "Secure HTTPS Article",
                    url: "https://example.com/article",
                    outlet_name: "Secure News",
                    published_at: null,
                    article_kind: "reporting",
                    match_kind: "direct",
                },
                {
                    id: 2,
                    title: "Standard HTTP Article",
                    url: "http://example.com/http-article",
                    outlet_name: "Standard News",
                    published_at: null,
                    article_kind: "reporting",
                    match_kind: "direct",
                },
            ];
            render(<RelatedNewsArticles articles={articles} />);

            const httpsLink = screen.getByRole("link", { name: /Secure HTTPS Article/i });
            expect(httpsLink).toHaveAttribute("href", "https://example.com/article");

            const httpLink = screen.getByRole("link", { name: /Standard HTTP Article/i });
            expect(httpLink).toHaveAttribute("href", "http://example.com/http-article");
        });

        it("refuses unsafe schemes (javascript:, data:) and renders title without link", () => {
            const articles: sway.INewsArticle[] = [
                {
                    id: 12,
                    title: "Exploit Attempt Javascript",
                    url: "javascript:alert(document.cookie)",
                    outlet_name: "Malicious Post",
                    published_at: null,
                    article_kind: "reporting",
                    match_kind: "direct",
                },
                {
                    id: 13,
                    title: "Exploit Attempt Data",
                    url: "data:text/html,<script>alert(1)</script>",
                    outlet_name: "Data Exploit",
                    published_at: null,
                    article_kind: "reporting",
                    match_kind: "direct",
                },
            ];
            render(<RelatedNewsArticles articles={articles} />);

            expect(screen.queryByRole("link")).toBeNull();
            expect(screen.getByText("Exploit Attempt Javascript")).toBeInTheDocument();
            expect(screen.getByText("Exploit Attempt Data")).toBeInTheDocument();
        });
    });

    describe("coverage and genre badges", () => {
        it("renders distinct badges for direct coverage versus surrounding-issue context", () => {
            const articles: sway.INewsArticle[] = [
                {
                    id: 1,
                    title: "Direct Coverage Analysis",
                    url: "https://example.com/direct",
                    outlet_name: "The Sun",
                    published_at: null,
                    article_kind: "reporting",
                    match_kind: "direct",
                },
                {
                    id: 2,
                    title: "Surrounding Transit Context",
                    url: "https://example.com/context",
                    outlet_name: "The Banner",
                    published_at: null,
                    article_kind: "reporting",
                    match_kind: "context",
                },
            ];
            render(<RelatedNewsArticles articles={articles} />);

            expect(screen.getByText("Direct coverage")).toBeInTheDocument();
            expect(screen.getByText("Context")).toBeInTheDocument();
        });

        it("labels opinions distinctly when article_kind is op_ed or editorial", () => {
            const articles: sway.INewsArticle[] = [
                {
                    id: 1,
                    title: "Guest Commentary on Transit",
                    url: "https://example.com/oped",
                    outlet_name: "Sun Opinion",
                    published_at: null,
                    article_kind: "op_ed",
                    match_kind: "direct",
                },
                {
                    id: 2,
                    title: "Editorial Board Endorsement",
                    url: "https://example.com/editorial",
                    outlet_name: "Banner Editorial Board",
                    published_at: null,
                    article_kind: "editorial",
                    match_kind: "direct",
                },
                {
                    id: 3,
                    title: "Straight Factual News",
                    url: "https://example.com/news",
                    outlet_name: "Local Wire",
                    published_at: null,
                    article_kind: "reporting",
                    match_kind: "direct",
                },
            ];
            render(<RelatedNewsArticles articles={articles} />);

            expect(screen.getByText("Op-ed")).toBeInTheDocument();
            expect(screen.getByText("Editorial")).toBeInTheDocument();
            expect(screen.queryByText("Reporting")).toBeNull();
        });
    });

    describe("title/URL-only (textless) article support", () => {
        it("renders textless articles with missing byline or date without error or layout corruption", () => {
            const articles: sway.INewsArticle[] = [
                {
                    id: 20,
                    title: "Minimal Link Only Article",
                    url: "https://example.com/minimal",
                    outlet_name: "Patch",
                    author_name: null,
                    published_at: null,
                    article_kind: "unknown",
                    match_kind: "direct",
                },
            ];
            render(<RelatedNewsArticles articles={articles} />);

            expect(screen.getByRole("link", { name: /Minimal Link Only Article/i })).toBeInTheDocument();
            expect(screen.getByText("Patch")).toBeInTheDocument();
            expect(screen.queryByText(/By /i)).toBeNull();
        });
    });

    describe("ordering preservation", () => {
        it("preserves article order as provided by server payload", () => {
            const articles: sway.INewsArticle[] = [
                {
                    id: 1,
                    title: "First Article",
                    url: "https://example.com/1",
                    outlet_name: "A",
                    published_at: null,
                    article_kind: "reporting",
                    match_kind: "direct",
                },
                {
                    id: 2,
                    title: "Second Article",
                    url: "https://example.com/2",
                    outlet_name: "B",
                    published_at: null,
                    article_kind: "reporting",
                    match_kind: "direct",
                },
                {
                    id: 3,
                    title: "Third Article",
                    url: "https://example.com/3",
                    outlet_name: "C",
                    published_at: null,
                    article_kind: "reporting",
                    match_kind: "direct",
                },
            ];
            render(<RelatedNewsArticles articles={articles} />);

            const links = screen.getAllByRole("link");
            expect(links[0]).toHaveTextContent("First Article");
            expect(links[1]).toHaveTextContent("Second Article");
            expect(links[2]).toHaveTextContent("Third Article");
        });
    });

    describe("layout variants", () => {
        const articles: sway.INewsArticle[] = [
            {
                id: 1,
                title: "Layout Test Article",
                url: "https://example.com/layout",
                outlet_name: "Local Press",
                published_at: "2026-05-01T12:00:00Z",
                article_kind: "reporting",
                match_kind: "direct",
            },
        ];

        it("renders default variant with Card and Related news title", () => {
            render(<RelatedNewsArticles articles={articles} variant="default" />);
            const container = screen.getByTestId("related-news-articles");
            expect(container).toBeInTheDocument();
            expect(screen.getByText("Related news")).toBeInTheDocument();
        });

        it("renders ballot variant with bal-section and bal-sectionlabel", () => {
            render(<RelatedNewsArticles articles={articles} variant="ballot" />);
            const section = screen.getByTestId("related-news-articles");
            expect(section).toHaveClass("bal-section");
            expect(screen.getByText("Related news")).toHaveClass("bal-sectionlabel");
        });

        it("renders banner variant with bn-section and bn-eyebrow", () => {
            render(<RelatedNewsArticles articles={articles} variant="banner" />);
            const section = screen.getByTestId("related-news-articles");
            expect(section).toHaveClass("bn-section");
            expect(screen.getByText("Related news")).toHaveClass("bn-eyebrow");
        });

        it("renders cornerstore variant with cs-card cs-card--wide and cs-card__title", () => {
            render(<RelatedNewsArticles articles={articles} variant="cornerstore" />);
            const card = screen.getByTestId("related-news-articles");
            expect(card).toHaveClass("cs-card");
            expect(card).toHaveClass("cs-card--wide");
            expect(screen.getByText("Related news")).toHaveClass("cs-card__title");
        });

        it("renders monochrome variant with mcb-section and mcb-sectionlabel", () => {
            render(<RelatedNewsArticles articles={articles} variant="monochrome" />);
            const section = screen.getByTestId("related-news-articles");
            expect(section).toHaveClass("mcb-section");
            expect(screen.getByText("Related news")).toHaveClass("mcb-sectionlabel");
        });

        it("renders service-manual variant with smb-section and smb-sectionlabel", () => {
            render(<RelatedNewsArticles articles={articles} variant="service-manual" />);
            const section = screen.getByTestId("related-news-articles");
            expect(section).toHaveClass("smb-section");
            expect(screen.getByText("Related news")).toHaveClass("smb-sectionlabel");
        });

        it("renders swiss-grid variant with sgb-row and sgb-index", () => {
            render(<RelatedNewsArticles articles={articles} variant="swiss-grid" />);
            const container = screen.getByTestId("related-news-articles");
            expect(container).toHaveClass("sgb-row");
            expect(screen.getByText("Related news")).toHaveClass("sgb-index");
        });
    });
});
