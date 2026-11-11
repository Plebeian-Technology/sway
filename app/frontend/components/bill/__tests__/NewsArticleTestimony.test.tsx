import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import type { sway } from "sway";

import NewsArticleTestimony from "app/frontend/components/bill/NewsArticleTestimony";

afterEach(cleanup);

describe("NewsArticleTestimony", () => {
    describe("empty and nil states", () => {
        it("renders null (0 DOM nodes) when testimonies prop is undefined", () => {
            const { container } = render(<NewsArticleTestimony testimonies={undefined} />);
            expect(container.firstChild).toBeNull();
            expect(container.innerHTML).toBe("");
        });

        it("renders null (0 DOM nodes) when testimonies prop is null", () => {
            const { container } = render(
                <NewsArticleTestimony testimonies={null as unknown as sway.INewsArticleTestimony[]} />,
            );
            expect(container.firstChild).toBeNull();
            expect(container.innerHTML).toBe("");
        });

        it("renders null (0 DOM nodes) when testimonies prop is an empty array", () => {
            const { container } = render(<NewsArticleTestimony testimonies={[]} />);
            expect(container.firstChild).toBeNull();
            expect(container.innerHTML).toBe("");
        });

        it("renders null (0 DOM nodes) when testimonies contains items but none match requested stance", () => {
            const opposeOnly: sway.INewsArticleTestimony[] = [
                {
                    id: 1,
                    author_name: "Elena Rostova",
                    outlet_name: "The Baltimore Banner",
                    url: "https://baltimorebanner.com/opinion/oppose-trees",
                    stance: "oppose",
                    argument: "Mandatory setbacks hurt small storefronts.",
                },
            ];
            const { container } = render(<NewsArticleTestimony testimonies={opposeOnly} stance="support" />);
            expect(container.firstChild).toBeNull();
            expect(container.innerHTML).toBe("");
            expect(screen.queryByTestId("news-article-testimony")).toBeNull();
        });
    });

    describe("stance segregation", () => {
        const sampleTestimonies: sway.INewsArticleTestimony[] = [
            {
                id: 10,
                author_name: "Marcus Vance",
                outlet_name: "The Baltimore Sun",
                url: "https://baltimoresun.com/opinion/support-trees",
                stance: "support",
                argument: "Urban forestry directly reduces summer heat island effects.",
            },
            {
                id: 11,
                author_name: "Elena Rostova",
                outlet_name: "The Baltimore Banner",
                url: "https://baltimorebanner.com/opinion/oppose-trees",
                stance: "oppose",
                argument: "Mandatory tree setbacks impose unfunded maintenance costs on small businesses.",
            },
        ];

        it("filters and displays only support testimonies when stance='support'", () => {
            render(<NewsArticleTestimony testimonies={sampleTestimonies} stance="support" />);

            expect(screen.getByText("Urban forestry directly reduces summer heat island effects.")).toBeInTheDocument();
            expect(screen.getByText(/Marcus Vance/)).toBeInTheDocument();
            expect(
                screen.queryByText("Mandatory tree setbacks impose unfunded maintenance costs on small businesses."),
            ).toBeNull();
            expect(screen.queryByText(/Elena Rostova/)).toBeNull();
        });

        it("filters and displays only oppose testimonies when stance='oppose'", () => {
            render(<NewsArticleTestimony testimonies={sampleTestimonies} stance="oppose" />);

            expect(
                screen.getByText("Mandatory tree setbacks impose unfunded maintenance costs on small businesses."),
            ).toBeInTheDocument();
            expect(screen.getByText(/Elena Rostova/)).toBeInTheDocument();
            expect(screen.queryByText("Urban forestry directly reduces summer heat island effects.")).toBeNull();
            expect(screen.queryByText(/Marcus Vance/)).toBeNull();
        });

        it("renders both stances with explicit labels when stance is omitted", () => {
            render(<NewsArticleTestimony testimonies={sampleTestimonies} />);

            expect(screen.getByText("Urban forestry directly reduces summer heat island effects.")).toBeInTheDocument();
            expect(
                screen.getByText("Mandatory tree setbacks impose unfunded maintenance costs on small businesses."),
            ).toBeInTheDocument();
            const items = screen.getAllByTestId("news-article-testimony");
            expect(items).toHaveLength(2);
        });
    });

    describe("content rendering and attribution", () => {
        it("renders argument text, author name byline, and outlet name", () => {
            const testimony: sway.INewsArticleTestimony = {
                id: 21,
                author_name: "Marcus Vance",
                outlet_name: "The Baltimore Sun",
                url: "https://baltimoresun.com/opinion/support-trees",
                stance: "support",
                argument: "Urban forestry directly reduces summer heat island effects.",
            };

            render(<NewsArticleTestimony testimonies={[testimony]} />);

            expect(screen.getByText("Urban forestry directly reduces summer heat island effects.")).toBeInTheDocument();
            expect(screen.getByText("By Marcus Vance")).toBeInTheDocument();
            expect(screen.getByText("The Baltimore Sun")).toBeInTheDocument();
        });

        it("attributes to Editorial Board when author_name is null or absent without orphaned 'By '", () => {
            const institutionalTestimony: sway.INewsArticleTestimony = {
                id: 22,
                author_name: null,
                outlet_name: "The Baltimore Banner",
                url: "https://baltimorebanner.com/opinion/editorial",
                stance: "support",
                argument: "Green infrastructure is a critical investment in climate resilience.",
            };

            render(<NewsArticleTestimony testimonies={[institutionalTestimony]} />);

            expect(
                screen.getByText("Green infrastructure is a critical investment in climate resilience."),
            ).toBeInTheDocument();
            expect(screen.getByText("The Baltimore Banner Editorial Board")).toBeInTheDocument();
            expect(screen.queryByText(/^By\s*$/i)).toBeNull();
        });

        it("keeps distinct op-ed authors at the same outlet as separate distinct items", () => {
            const sameOutletDifferentAuthors: sway.INewsArticleTestimony[] = [
                {
                    id: 31,
                    author_name: "Dr. Alistair Finch",
                    outlet_name: "The Baltimore Banner",
                    url: "https://baltimorebanner.com/opinion/finch",
                    stance: "support",
                    argument: "Canopy coverage increases pedestrian safety and air quality.",
                },
                {
                    id: 32,
                    author_name: "Sarah Jenkins",
                    outlet_name: "The Baltimore Banner",
                    url: "https://baltimorebanner.com/opinion/jenkins",
                    stance: "support",
                    argument: "Neighborhood greening improves stormwater runoff capture.",
                },
            ];

            render(<NewsArticleTestimony testimonies={sameOutletDifferentAuthors} />);

            const items = screen.getAllByTestId("news-article-testimony");
            expect(items).toHaveLength(2);
            expect(screen.getByText("By Dr. Alistair Finch")).toBeInTheDocument();
            expect(screen.getByText("By Sarah Jenkins")).toBeInTheDocument();
            expect(screen.getAllByText("The Baltimore Banner")).toHaveLength(2);
        });
    });

    describe("badging and demarcation", () => {
        it("renders a distinct visual badge labeling published commentary", () => {
            const testimony: sway.INewsArticleTestimony = {
                id: 41,
                author_name: "Marcus Vance",
                outlet_name: "The Baltimore Sun",
                url: "https://baltimoresun.com/opinion/trees",
                stance: "support",
                argument: "Urban forestry directly reduces summer heat island effects.",
            };

            render(<NewsArticleTestimony testimonies={[testimony]} />);

            expect(screen.getByText("News commentary")).toBeInTheDocument();
        });
    });

    describe("link security & accessibility", () => {
        it("renders citation link with href, target='_blank', rel='noopener noreferrer', and screen reader text", () => {
            const testimony: sway.INewsArticleTestimony = {
                id: 51,
                author_name: "Marcus Vance",
                outlet_name: "The Baltimore Sun",
                url: "https://baltimoresun.com/opinion/trees",
                stance: "support",
                argument: "Urban forestry directly reduces summer heat island effects.",
            };

            render(<NewsArticleTestimony testimonies={[testimony]} />);

            const link = screen.getByRole("link", { name: /The Baltimore Sun/i });
            expect(link).toHaveAttribute("href", "https://baltimoresun.com/opinion/trees");
            expect(link).toHaveAttribute("target", "_blank");
            expect(link).toHaveAttribute("rel", "noopener noreferrer");
            expect(screen.getByText(/\(opens in new tab\)/i)).toBeInTheDocument();
        });
    });

    describe("malicious URL scheme refusal", () => {
        it("refuses javascript: scheme and renders citation as inert text without anchor", () => {
            const exploitTestimony: sway.INewsArticleTestimony = {
                id: 61,
                author_name: "Attacker",
                outlet_name: "Malicious Outlet",
                url: "javascript:alert(document.cookie)",
                stance: "support",
                argument: "Exploit attempt in news argument.",
            };

            render(<NewsArticleTestimony testimonies={[exploitTestimony]} />);

            expect(screen.queryByRole("link")).toBeNull();
            expect(screen.getByText("Malicious Outlet")).toBeInTheDocument();
            expect(screen.getByText("Exploit attempt in news argument.")).toBeInTheDocument();
        });

        it("refuses data: scheme and renders citation as inert text", () => {
            const dataTestimony: sway.INewsArticleTestimony = {
                id: 62,
                author_name: "Attacker",
                outlet_name: "Data Outlet",
                url: "data:text/html,<script>alert(1)</script>",
                stance: "oppose",
                argument: "Data URI exploit attempt.",
            };

            render(<NewsArticleTestimony testimonies={[dataTestimony]} />);

            expect(screen.queryByRole("link")).toBeNull();
            expect(screen.getByText("Data Outlet")).toBeInTheDocument();
        });

        it("refuses file: and vbscript: protocols, strictly permitting only http: and https:", () => {
            const fileTestimony: sway.INewsArticleTestimony = {
                id: 63,
                author_name: "Local Attacker",
                outlet_name: "Local File Outlet",
                url: "file:///etc/passwd",
                stance: "oppose",
                argument: "File scheme attempt.",
            };

            render(<NewsArticleTestimony testimonies={[fileTestimony]} />);

            expect(screen.queryByRole("link")).toBeNull();
            expect(screen.getByText("Local File Outlet")).toBeInTheDocument();
        });
    });

    describe("volumetric handling & order preservation", () => {
        it("renders multiple testimonies in array order without key collisions", () => {
            const multiple: sway.INewsArticleTestimony[] = [
                {
                    id: 71,
                    author_name: "Author 1",
                    outlet_name: "Outlet 1",
                    url: "https://example.com/1",
                    stance: "support",
                    argument: "First argument in payload.",
                },
                {
                    id: 72,
                    author_name: "Author 2",
                    outlet_name: "Outlet 2",
                    url: "https://example.com/2",
                    stance: "support",
                    argument: "Second argument in payload.",
                },
                {
                    id: 73,
                    author_name: "Author 3",
                    outlet_name: "Outlet 3",
                    url: "https://example.com/3",
                    stance: "support",
                    argument: "Third argument in payload.",
                },
            ];

            render(<NewsArticleTestimony testimonies={multiple} />);

            const items = screen.getAllByTestId("news-article-testimony");
            expect(items).toHaveLength(3);
            expect(items[0]).toHaveTextContent("First argument in payload.");
            expect(items[1]).toHaveTextContent("Second argument in payload.");
            expect(items[2]).toHaveTextContent("Third argument in payload.");
        });
    });

    describe("layout variants", () => {
        const testimony: sway.INewsArticleTestimony = {
            id: 81,
            author_name: "Marcus Vance",
            outlet_name: "The Baltimore Sun",
            url: "https://baltimoresun.com/opinion/trees",
            stance: "support",
            argument: "Urban forestry directly reduces summer heat island effects.",
        };

        it("renders default variant", () => {
            render(<NewsArticleTestimony testimonies={[testimony]} variant="default" />);
            const item = screen.getByTestId("news-article-testimony");
            expect(item).toBeInTheDocument();
        });

        it("renders ballot variant with bal-org class", () => {
            render(<NewsArticleTestimony testimonies={[testimony]} variant="ballot" />);
            const item = screen.getByTestId("news-article-testimony");
            expect(item).toHaveClass("bal-org");
        });

        it("renders banner variant with bn-prov class", () => {
            render(<NewsArticleTestimony testimonies={[testimony]} variant="banner" />);
            const item = screen.getByTestId("news-article-testimony");
            expect(item).toHaveClass("bn-prov");
        });

        it("renders cornerstore variant with cs-org class", () => {
            render(<NewsArticleTestimony testimonies={[testimony]} variant="cornerstore" />);
            const item = screen.getByTestId("news-article-testimony");
            expect(item).toHaveClass("cs-org");
        });
    });
});
