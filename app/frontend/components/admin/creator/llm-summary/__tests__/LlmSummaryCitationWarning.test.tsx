import { render, screen } from "@testing-library/react";
import LlmSummaryCitationWarning from "app/frontend/components/admin/creator/llm-summary/LlmSummaryCitationWarning";

describe("LlmSummaryCitationWarning", () => {
    it("returns null when citationsValid is true", () => {
        const { container } = render(
            <LlmSummaryCitationWarning citationsValid={true} invalidCitations={["art_14__sec_301"]} />,
        );
        expect(container.firstChild).toBeNull();
    });

    it("returns null when citationsValid is null", () => {
        const { container } = render(
            <LlmSummaryCitationWarning citationsValid={null} invalidCitations={["art_14__sec_301"]} />,
        );
        expect(container.firstChild).toBeNull();
    });

    it("returns null when invalidCitations is empty", () => {
        const { container } = render(<LlmSummaryCitationWarning citationsValid={false} invalidCitations={[]} />);
        expect(container.firstChild).toBeNull();
    });

    it("returns null when invalidCitations is null", () => {
        const { container } = render(<LlmSummaryCitationWarning citationsValid={false} invalidCitations={null} />);
        expect(container.firstChild).toBeNull();
    });

    it("renders the singular title and key for one invalid citation", () => {
        render(<LlmSummaryCitationWarning citationsValid={false} invalidCitations={["art_14__sec_301"]} />);

        expect(screen.getByTestId("llm-citation-warning")).toBeInTheDocument();
        expect(screen.getByText("Unverified citation")).toBeInTheDocument();
        expect(screen.getByText("art_14__sec_301")).toBeInTheDocument();
    });

    it("renders the plural title, comma-joined keys, and the non-blocking trailer for multiple invalid citations", () => {
        render(
            <LlmSummaryCitationWarning
                citationsValid={false}
                invalidCitations={["art_14__sec_301", "art_14__sec_302"]}
            />,
        );

        expect(screen.getByText("Unverified citations")).toBeInTheDocument();
        expect(screen.getByText("art_14__sec_301, art_14__sec_302")).toBeInTheDocument();
        expect(screen.getByText(/does not block saving or approving/)).toBeInTheDocument();
    });
});
