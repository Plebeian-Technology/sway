import React from "react";
import { fireEvent, render, screen } from "@testing-library/react-native";

import NewsEvidenceControls, {
    type EvidenceArticle,
} from "../../../../src/components/admin/billCreator/NewsEvidenceControls";

const article = (overrides: Partial<EvidenceArticle>): EvidenceArticle => ({
    id: 1,
    approved: true,
    has_text: true,
    url: "https://www.thebaltimorebanner.com/rent",
    title: "Council weighs rent cap",
    source_name: "The Baltimore Banner",
    ...overrides,
});

// @lat: [[mobile-bill-creator#Sections#The bill fields section#Declaring news evidence]]
describe("NewsEvidenceControls", () => {
    it("offers the two declarations and reports the one chosen", () => {
        const onChange = jest.fn();
        render(<NewsEvidenceControls summary="" newsUsage="none" onChangeNewsUsage={onChange} articles={[]} />);

        expect(screen.getByText("News Evidence Usage")).toBeTruthy();
        expect(screen.getByTestId("admin-news-evidence-none").props.accessibilityState).toEqual(
            expect.objectContaining({ checked: true }),
        );
        expect(screen.getByTestId("admin-news-evidence-cited").props.accessibilityState).toEqual(
            expect.objectContaining({ checked: false }),
        );

        fireEvent.press(screen.getByTestId("admin-news-evidence-cited"));

        expect(onChange).toHaveBeenCalledWith("cited");
    });

    it("warns when the summary links outside official sources but declares no news", () => {
        render(
            <NewsEvidenceControls
                summary="Read [the Banner](https://www.thebaltimorebanner.com/rent)."
                newsUsage="none"
                onChangeNewsUsage={jest.fn()}
                articles={[]}
            />,
        );

        expect(screen.getByTestId("admin-news-evidence-none-warning")).toHaveTextContent(
            /Notice: External links detected in summary prose/,
        );
    });

    it("does not warn for an official link or once news is cited", () => {
        const { rerender } = render(
            <NewsEvidenceControls
                summary="See [the bill](https://baltimore.legistar.com/25-0042)."
                newsUsage="none"
                onChangeNewsUsage={jest.fn()}
                articles={[]}
            />,
        );
        expect(screen.queryByTestId("admin-news-evidence-none-warning")).toBeNull();

        rerender(
            <NewsEvidenceControls
                summary="Read [the Banner](https://www.thebaltimorebanner.com/rent)."
                newsUsage="cited"
                onChangeNewsUsage={jest.fn()}
                articles={[]}
            />,
        );
        expect(screen.queryByTestId("admin-news-evidence-none-warning")).toBeNull();
    });

    it("lists the approved articles with text once news is cited", () => {
        const articles = [
            article({ id: 1 }),
            article({ id: 2, approved: false, title: "Unapproved story" }),
            article({ id: 3, has_text: false, title: "Link-only story" }),
        ];
        const { rerender } = render(
            <NewsEvidenceControls summary="" newsUsage="none" onChangeNewsUsage={jest.fn()} articles={articles} />,
        );
        expect(screen.queryByTestId("admin-news-evidence-articles")).toBeNull();

        rerender(
            <NewsEvidenceControls summary="" newsUsage="cited" onChangeNewsUsage={jest.fn()} articles={articles} />,
        );

        expect(screen.getByTestId("admin-news-evidence-article-1")).toHaveTextContent(/Council weighs rent cap/);
        expect(screen.getByTestId("admin-news-evidence-article-1")).toHaveTextContent(
            /https:\/\/www\.thebaltimorebanner\.com\/rent/,
        );
        expect(screen.queryByTestId("admin-news-evidence-article-2")).toBeNull();
        expect(screen.queryByTestId("admin-news-evidence-article-3")).toBeNull();
    });

    it("says when no approved article has text to cite", () => {
        render(
            <NewsEvidenceControls
                summary=""
                newsUsage="cited"
                onChangeNewsUsage={jest.fn()}
                articles={[article({ id: 3, has_text: false })]}
            />,
        );

        expect(screen.getByTestId("admin-news-evidence-no-articles")).toBeTruthy();
    });
});
