// @lat: [[news-claim-assessment#Two-phase verification architecture]]

import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";

import BillSummaryMarkdown from "app/frontend/components/bill/BillSummaryMarkdown";

afterEach(cleanup);

describe("M20 Challenger 1: BillSummaryMarkdown reader visibility probes", () => {
    it("probes 4-space indented reference definitions (indented code block in CommonMark)", () => {
        const summary = "The city council approved 50 new parks.\n\n    [source]: https://thebanner.com/parks";
        const { container } = render(<BillSummaryMarkdown summary={summary} />);

        const codeElement = container.querySelector("pre code");
        const links = container.querySelectorAll("a");

        expect(codeElement).not.toBeNull();
        expect(codeElement?.textContent).toContain("[source]: https://thebanner.com/parks");
        expect(links).toHaveLength(0);
        expect(screen.queryByRole("link")).toBeNull();
    });

    it("probes 4-space indented plain URLs in code blocks", () => {
        const summary = "Code block example:\n\n    https://thebanner.com/parks";
        const { container } = render(<BillSummaryMarkdown summary={summary} />);

        const codeElement = container.querySelector("pre code");
        const links = container.querySelectorAll("a");

        expect(codeElement).not.toBeNull();
        expect(codeElement?.textContent).toContain("https://thebanner.com/parks");
        expect(links).toHaveLength(0);
        expect(screen.queryByRole("link")).toBeNull();
    });

    it("probes shortcut reference link followed by a colon in English prose: [source]:", () => {
        const summary = "According to [source]: the vote passed.\n\n[source]: https://thebanner.com/colon-probe";
        const { container } = render(<BillSummaryMarkdown summary={summary} />);

        const links = container.querySelectorAll("a");
        expect(links.length).toBeGreaterThan(0);
        expect(links[0]).toHaveAttribute("href", "https://thebanner.com/colon-probe");
    });
});
