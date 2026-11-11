import { render, screen } from "@testing-library/react";
import TestimonyRecordBar from "app/frontend/components/admin/creator/testimony-report/TestimonyRecordBar";

describe("TestimonyRecordBar", () => {
    it("renders neither the bar nor its sentence when the total is zero", () => {
        const { container } = render(
            <TestimonyRecordBar
                reachedChars={0}
                removedChars={0}
                repairAddedChars={0}
                leftOutChars={0}
                totalChars={0}
            />,
        );

        expect(container).toBeEmptyDOMElement();
    });

    // Bill 62, the phase's reference render (67-UI-SPEC.md E3 "populated").
    it("draws the reference render's three segments at true scale", () => {
        render(
            <TestimonyRecordBar
                reachedChars={180253}
                removedChars={857270}
                repairAddedChars={0}
                leftOutChars={0}
                totalChars={1037523}
            />,
        );

        const bar = screen.getByTestId("testimony-record-bar");
        expect(bar.querySelector('[data-segment="reached"]')).toHaveStyle({ width: "17.3734%" });
        expect(bar.querySelector('[data-segment="removed"]')).toHaveStyle({ width: "82.6266%" });
        expect(bar.querySelector('[data-segment="left-out"]')).toHaveStyle({ width: "0.0000%" });
        expect(bar).toHaveTextContent(
            "180,253 of 1,037,523 characters reached the model. 857,270 were removed as repeated text. 0 were left out.",
        );
    });

    it("renders a segment whose count is zero at zero width", () => {
        render(
            <TestimonyRecordBar
                reachedChars={900}
                removedChars={100}
                repairAddedChars={0}
                leftOutChars={0}
                totalChars={1000}
            />,
        );

        const bar = screen.getByTestId("testimony-record-bar");
        expect(bar.querySelector('[data-segment="left-out"]')).toHaveStyle({ width: "0.0000%" });
    });

    // Proves the two-pixel floor and that the widths still sum to the container: 400 of 100,000
    // is 0.4%, under the floor, so it renders wider than its true share — and the extra comes out
    // of the widest segment (reached, 90%) rather than the total.
    it("floors a 0.4 percent segment and takes the difference out of the widest segment", () => {
        render(
            <TestimonyRecordBar
                reachedChars={90000}
                removedChars={9600}
                repairAddedChars={0}
                leftOutChars={400}
                totalChars={100000}
            />,
        );

        const bar = screen.getByTestId("testimony-record-bar");
        const reached = bar.querySelector('[data-segment="reached"]') as HTMLElement;
        const removed = bar.querySelector('[data-segment="removed"]') as HTMLElement;
        const leftOut = bar.querySelector('[data-segment="left-out"]') as HTMLElement;

        expect(leftOut).toHaveStyle({ width: "1.0000%" });
        expect(reached).toHaveStyle({ width: "89.4000%" });
        expect(removed).toHaveStyle({ width: "9.6000%" });

        const sum = parseFloat(reached.style.width) + parseFloat(removed.style.width) + parseFloat(leftOut.style.width);
        expect(sum).toBeCloseTo(100, 4);
    });

    // WR-02. Testimony::CoverageReport#removed_chars is total - cleaned and is
    // deliberately not clamped, because the character repair replaces each
    // broken character with a two- or three-character pair and so ADDS
    // characters. On real testimony today that is the ordinary case, not a
    // corner one, so every real bill rendered a negative width — which is
    // invalid CSS, is dropped, and leaves the div at flex auto size.
    describe("when the repair grew the text, so nothing was removed", () => {
        it("draws no removed segment, and the three widths still sum to 100", () => {
            render(
                <TestimonyRecordBar
                    reachedChars={140000}
                    removedChars={0}
                    repairAddedChars={4231}
                    leftOutChars={4231}
                    totalChars={140000}
                />,
            );

            const bar = screen.getByTestId("testimony-record-bar");
            const reached = bar.querySelector('[data-segment="reached"]') as HTMLElement;
            const removed = bar.querySelector('[data-segment="removed"]') as HTMLElement;
            const leftOut = bar.querySelector('[data-segment="left-out"]') as HTMLElement;

            [reached, removed, leftOut].forEach((segment) => {
                expect(parseFloat(segment.style.width)).toBeGreaterThanOrEqual(0);
            });
            const sum =
                parseFloat(reached.style.width) + parseFloat(removed.style.width) + parseFloat(leftOut.style.width);
            expect(sum).toBeCloseTo(100, 4);
        });

        it("says nothing about characters removed, rather than saying a negative number were", () => {
            render(
                <TestimonyRecordBar
                    reachedChars={140000}
                    removedChars={0}
                    repairAddedChars={4231}
                    leftOutChars={4231}
                    totalChars={140000}
                />,
            );

            const bar = screen.getByTestId("testimony-record-bar");
            expect(bar).not.toHaveTextContent("-4,231");
            expect(bar).not.toHaveTextContent("removed as repeated text");
            expect(bar).toHaveTextContent("4,231 were left out.");
            expect(bar).toHaveTextContent("of 140,000");
            expect(bar).toHaveTextContent("4,231 were added when broken characters were repaired");
        });
    });

    it("is hidden from assistive technology and carries no progress role", () => {
        render(
            <TestimonyRecordBar
                reachedChars={900}
                removedChars={100}
                repairAddedChars={0}
                leftOutChars={0}
                totalChars={1000}
            />,
        );

        const bar = screen.getByTestId("testimony-record-bar");
        expect(bar.querySelector("[aria-hidden='true']")).toBeInTheDocument();
        expect(screen.queryByRole("progressbar")).toBeNull();
    });

    it("never renders a hard-coded color literal or arbitrary var() class", () => {
        const { container } = render(
            <TestimonyRecordBar
                reachedChars={900}
                removedChars={100}
                repairAddedChars={0}
                leftOutChars={0}
                totalChars={1000}
            />,
        );

        expect(container.innerHTML).not.toMatch(/#[0-9a-fA-F]{6}|rgb\(|hsl\(|\[var\(--/);
    });

    it("never uses select-none", () => {
        const { container } = render(
            <TestimonyRecordBar
                reachedChars={900}
                removedChars={100}
                repairAddedChars={0}
                leftOutChars={0}
                totalChars={1000}
            />,
        );

        expect(container.innerHTML).not.toMatch(/select-none/);
    });
});
