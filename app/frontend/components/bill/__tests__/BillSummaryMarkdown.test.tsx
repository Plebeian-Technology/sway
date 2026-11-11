// @lat: [[news-claim-assessment#Two-phase verification architecture]]

import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";

import BillSummaryMarkdown from "app/frontend/components/bill/BillSummaryMarkdown";

afterEach(cleanup);

describe("BillSummaryMarkdown — GitHub-flavored markdown", () => {
    it("renders tables, task lists, strikethrough and fenced code", () => {
        const summary = [
            "| Org | Stance |",
            "| --- | --- |",
            "| Sierra Club | Support |",
            "",
            "- [x] filed",
            "- [ ] heard",
            "",
            "~~withdrawn~~",
            "",
            "```",
            "Sec. 1",
            "```",
        ].join("\n");
        const { container } = render(<BillSummaryMarkdown summary={summary} />);

        expect(container.querySelectorAll("table th")).toHaveLength(2);
        expect(container.querySelector("td")?.textContent).toBe("Sierra Club");
        expect(container.querySelectorAll("li.task-list-item input[type=checkbox]")).toHaveLength(2);
        expect(container.querySelector("del")?.textContent).toBe("withdrawn");
        expect(container.querySelector("pre code")?.textContent).toBe("Sec. 1\n");
    });
});

describe("BillSummaryMarkdown — reader link visibility controls", () => {
    it("renders inert text without an anchor for file:, javascript:, and data: schemes", () => {
        const { container } = render(
            <BillSummaryMarkdown summary="See [Local File](file:///etc/passwd), [Root](file:///), [Exploit](javascript:alert(1)), and [Data](data:text/html,xss)." />,
        );

        expect(screen.queryByRole("link")).toBeNull();
        expect(container.querySelectorAll("a")).toHaveLength(0);
        const spans = container.querySelectorAll("span");
        expect(spans).toHaveLength(4);
        expect(spans[0]?.textContent).toBe("Local File");
        expect(container.textContent).toContain("See Local File, Root, Exploit, and Data.");
    });

    it("renders a link that is not a valid absolute URL without throwing", () => {
        const { container } = render(<BillSummaryMarkdown summary="See [the filing](httpfoo) or [this](http://)." />);

        expect(screen.getByRole("link", { name: "the filing" })).toHaveAttribute("href", "httpfoo");
        expect(screen.queryByRole("link", { name: "this" })).toBeNull();
        expect(container.querySelector("span")?.textContent).toBe("this");
    });

    it("renders a visible anchor link for inline markdown links", () => {
        const summary = "The city council approved 50 new parks. [Source](https://thebanner.com/politics/parks)";
        const { container } = render(<BillSummaryMarkdown summary={summary} />);

        const link = screen.getByRole("link", { name: /Source/i });
        expect(link).toBeInTheDocument();
        expect(link).toHaveAttribute("href", "https://thebanner.com/politics/parks");
        expect(link).toHaveAttribute("target", "_blank");
        expect(link).toHaveAttribute("rel", "noopener noreferrer");
        expect(container.querySelectorAll("a")).toHaveLength(1);
    });

    it("renders a visible anchor link for used reference-style links", () => {
        const summary =
            "The city council approved 50 new parks. [Source][1]\n\n[1]: https://thebanner.com/politics/parks";
        const { container } = render(<BillSummaryMarkdown summary={summary} />);

        const link = screen.getByRole("link", { name: /Source/i });
        expect(link).toBeInTheDocument();
        expect(link).toHaveAttribute("href", "https://thebanner.com/politics/parks");
        expect(link).toHaveAttribute("target", "_blank");
        expect(link).toHaveAttribute("rel", "noopener noreferrer");
        expect(container.querySelectorAll("a")).toHaveLength(1);
    });

    it("does not render any anchor link for unused reference definitions", () => {
        const summary = "The city council approved 50 new parks.\n\n[source]: https://thebanner.com/politics/parks";
        const { container } = render(<BillSummaryMarkdown summary={summary} />);

        expect(screen.queryByRole("link")).toBeNull();
        expect(container.querySelectorAll("a")).toHaveLength(0);
        expect(container.textContent).toContain("The city council approved 50 new parks.");
        expect(container.textContent).not.toContain("https://thebanner.com/politics/parks");
        expect(container.textContent).not.toContain("[source]");
    });

    it("does not render anchor links for URLs inside HTML comments or non-link markup", () => {
        const summary = "The city council approved 50 new parks. <!-- https://thebanner.com/politics/parks -->";
        const { container } = render(<BillSummaryMarkdown summary={summary} />);

        expect(screen.queryByRole("link")).toBeNull();
        expect(container.querySelectorAll("a")).toHaveLength(0);
    });

    it("renders visible links only for used citations when mixed with an unused reference definition", () => {
        const summary = [
            "The council funded 50 parks per [Banner Report](https://thebanner.com/politics/parks).",
            "Additional details were confirmed by [The Sun][sun-ref].",
            "",
            "[sun-ref]: https://baltimoresun.com/news/parks",
            "[unused-ref]: https://unused-source.org/hidden",
        ].join("\n");

        const { container } = render(<BillSummaryMarkdown summary={summary} />);

        const links = container.querySelectorAll("a");
        expect(links).toHaveLength(2);

        const hrefs = Array.from(links).map((a) => a.getAttribute("href"));
        expect(hrefs).toContain("https://thebanner.com/politics/parks");
        expect(hrefs).toContain("https://baltimoresun.com/news/parks");
        expect(hrefs).not.toContain("https://unused-source.org/hidden");
    });

    it("renders plain GFM autolinks as visible anchors", () => {
        const summary = "Read the reporting directly at https://thebanner.com/politics/parks for more details.";
        const { container } = render(<BillSummaryMarkdown summary={summary} />);

        const link = screen.getByRole("link");
        expect(link).toBeInTheDocument();
        expect(link).toHaveAttribute("href", "https://thebanner.com/politics/parks");
        expect(container.querySelectorAll("a")).toHaveLength(1);
    });

    it("renders empty placeholder when summary is undefined or blank", () => {
        const { container } = render(<BillSummaryMarkdown summary={undefined} />);
        expect(container.querySelectorAll("a")).toHaveLength(0);
        expect(container.querySelector(".bill-summary-markdown")).not.toBeNull();
    });

    it("renders protocol-relative links with external link icon", () => {
        const summary = "Check [External Source](//thebanner.com/politics/parks).";
        const { container } = render(<BillSummaryMarkdown summary={summary} />);

        const link = screen.getByRole("link", { name: /External Source/i });
        expect(link).toHaveAttribute("href", "//thebanner.com/politics/parks");
        expect(link).toHaveAttribute("target", "_blank");
        expect(container.querySelector("svg.lucide-external-link")).toBeInTheDocument();
    });

    it("disallows markdown images while keeping safe anchor links rendering", () => {
        const summary = "Summary text ![beacon](https://example.com/pixel.png) and [source](https://example.com/doc)";
        const { container } = render(<BillSummaryMarkdown summary={summary} />);

        expect(container.querySelectorAll("img")).toHaveLength(0);
        const link = screen.getByRole("link", { name: /source/i });
        expect(link).toHaveAttribute("href", "https://example.com/doc");
    });
});
