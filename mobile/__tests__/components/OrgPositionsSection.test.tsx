import React from "react";
import { render, screen } from "@testing-library/react-native";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { OrgPositionsSection, type OrgPosition } from "../../src/components/OrgPositionsSection";
import type { NewsArticleTestimony as NewsArticleTestimonyType } from "../../src/types/bill";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn().mockResolvedValue(undefined),
    ImpactFeedbackStyle: { Light: "light" },
}));

const forPosition = {
    id: 1,
    support: "FOR" as const,
    organization: { name: "ACLU" },
    summary: "Supports civil liberties.",
};

const againstPosition = {
    id: 2,
    support: "AGAINST" as const,
    organization: { name: "Chamber of Commerce" },
    summary: "Opposes business regulation.",
};

const newsSupport: NewsArticleTestimonyType = {
    id: 7,
    author_name: "Emily Vance",
    outlet_name: "The Baltimore Banner",
    stance: "support",
    url: "https://thebaltimorebanner.com/opinion/support-transit",
    argument: "Investing in regional transit expands economic opportunity across Baltimore.",
};

const wrap = (positions: OrgPosition[] = [], newsTestimonies?: NewsArticleTestimonyType[]) =>
    render(
        <ThemeProvider initialMode="light">
            <OrgPositionsSection positions={positions} newsTestimonies={newsTestimonies} />
        </ThemeProvider>,
    );

describe("OrgPositionsSection", () => {
    test("Test 1: with positions=[], renders both cards with the empty lines from PARITY_COPY", () => {
        wrap([]);
        expect(screen.getByText("Sway has not yet found any statements of support for this legislation.")).toBeTruthy();
        expect(
            screen.getByText("Sway has not yet found any statements of opposition for this legislation."),
        ).toBeTruthy();
    });

    test("Test 2: with one FOR position, why-support card shows it; why-oppose shows its empty line", () => {
        wrap([forPosition]);
        expect(screen.getByText("ACLU")).toBeTruthy();
        expect(
            screen.getByText("Sway has not yet found any statements of opposition for this legislation."),
        ).toBeTruthy();
    });

    test("Test 3: with one AGAINST position, why-oppose card shows it; why-support shows its empty line", () => {
        wrap([againstPosition]);
        expect(screen.getByText("Chamber of Commerce")).toBeTruthy();
        expect(screen.getByText("Sway has not yet found any statements of support for this legislation.")).toBeTruthy();
    });

    test("Test 4: with both FOR and AGAINST, both cards render their respective positions", () => {
        wrap([forPosition, againstPosition]);
        expect(screen.getByText("ACLU")).toBeTruthy();
        expect(screen.getByText("Chamber of Commerce")).toBeTruthy();
    });

    test("Test 5: each position renders organization.name and summary text", () => {
        wrap([forPosition]);
        expect(screen.getByText("ACLU")).toBeTruthy();
        expect(screen.getByText("Supports civil liberties.")).toBeTruthy();
    });

    test("Test 6: section has testID=org-positions-section", () => {
        wrap([]);
        expect(screen.getByTestId("org-positions-section")).toBeTruthy();
    });
    test.each([
        ["null", null],
        ["empty string", ""],
        ["absent", undefined],
    ])("drops a position whose summary is %s, as the website does", (_label, summary) => {
        wrap([{ ...forPosition, summary }, againstPosition]);

        expect(screen.queryByText("ACLU")).toBeNull();
        expect(screen.getByText("Chamber of Commerce")).toBeTruthy();
    });

    test("shows each card's empty line when every position lacks a summary", () => {
        wrap([
            { ...forPosition, summary: null },
            { ...againstPosition, summary: "" },
        ]);

        expect(screen.queryByText("ACLU")).toBeNull();
        expect(screen.queryByText("Chamber of Commerce")).toBeNull();
        expect(screen.getByTestId("org-positions-empty-support")).toBeTruthy();
        expect(screen.getByTestId("org-positions-empty-oppose")).toBeTruthy();
    });

    test("keeps the original order of the positions that survive", () => {
        wrap([
            { ...forPosition, id: 10, organization: { name: "Zeta" } },
            { ...forPosition, id: 11, organization: { name: "Alpha" }, summary: null },
            { ...forPosition, id: 12, organization: { name: "Beta" } },
        ]);

        const names = screen.getAllByTestId("org-position-name").map((node) => node.props.children);
        expect(names).toEqual(["Zeta", "Beta"]);
    });

    test("renders each empty line as one inline muted line, not an EmptyState block", () => {
        wrap([]);

        const support = screen.getByTestId("org-positions-empty-support");
        const oppose = screen.getByTestId("org-positions-empty-oppose");
        expect(support.props.children).toBe(PARITY_COPY.org.noSupport);
        expect(oppose.props.children).toBe(PARITY_COPY.org.noOppose);
        expect(screen.queryByLabelText(PARITY_COPY.org.noSupport)).toBeNull();
        expect(screen.queryByLabelText(PARITY_COPY.org.noOppose)).toBeNull();
    });

    test("keeps a stance's empty line when only news testimony exists for it", () => {
        wrap([], [newsSupport]);

        expect(screen.getByTestId("org-positions-empty-support")).toBeTruthy();
        expect(screen.getByText(newsSupport.argument)).toBeTruthy();
    });

    test("exposes both card titles as headings", () => {
        wrap([]);

        const headings = screen.getAllByRole("header").map((node) => node.props.children);
        expect(headings).toEqual([PARITY_COPY.bill.content.whySupport, PARITY_COPY.bill.content.whyOppose]);
    });

    test("lets readers select organization names and summaries", () => {
        wrap([forPosition]);

        expect(screen.getByTestId("org-position-name").props.selectable).toBe(true);
        expect(screen.getByText("Supports civil liberties.").props.selectable).toBe(true);
    });

    test("renders a position summary as markdown, forwards onOpenUrl, and displays the AI-unreviewed notice when flagged", () => {
        const onOpenUrl = jest.fn();
        render(
            <ThemeProvider initialMode="light">
                <OrgPositionsSection
                    onOpenUrl={onOpenUrl}
                    positions={[
                        {
                            ...forPosition,
                            summary:
                                "Protects **free speech** per [Source](https://example.com/report).\n\n- first reason\n- second reason",
                            summary_ai_unreviewed: true,
                        },
                    ]}
                />
            </ThemeProvider>,
        );

        expect(screen.getByText("free speech")).toBeTruthy();
        expect(screen.getByText("first reason")).toBeTruthy();
        expect(screen.getAllByText("•")).toHaveLength(2);
        expect(screen.queryByText(/\*\*/)).toBeNull();
        expect(screen.getByTestId("ai-unreviewed-notice")).toBeTruthy();
    });
});

describe("OrgPositionsSection affiliation labels", () => {
    test("shows the notice once and tags each position by who wrote it", () => {
        wrap([
            { ...forPosition, source_kind: "organization" },
            { ...againstPosition, source_kind: "news_article" },
        ]);

        expect(screen.getAllByText(PARITY_COPY.orgs.listNotice)).toHaveLength(1);
        const tags = screen.getAllByTestId("org-position-source-tag").map((tag) => tag.props.children);
        expect(tags.toSorted()).toEqual(["Compiled by Sway", "Posted by ACLU"]);
    });

    test("tags a position with no recorded origin as compiled by Sway", () => {
        wrap([{ ...forPosition, source_kind: null }]);

        expect(screen.getByTestId("org-position-source-tag").props.children).toBe(PARITY_COPY.orgs.compiledBySway);
    });

    test("shows no notice when there are no positions", () => {
        wrap([]);

        expect(screen.queryByText(PARITY_COPY.orgs.listNotice)).toBeNull();
    });
});
