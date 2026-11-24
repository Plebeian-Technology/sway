// @lat: [[mobile-jest-first-pass-test-notes#LegislatorChartsPanel.test.tsx]]

// ── Fake modules. These get lifted above the imports below ───────────────────

// react-native-svg — a stand-in that keeps each Rect's width prop somewhere the
// tests can read it back.
jest.mock("react-native-svg", () => {
    /* oxlint-disable @typescript-eslint/no-require-imports */
    const ReactMod = require("react");
    const RNMod = require("react-native");
    /* oxlint-enable @typescript-eslint/no-require-imports */

    const Svg = ({
        children,
        accessibilityLabel,
        testID,
    }: {
        children?: React.ReactNode;
        width?: number;
        height?: number;
        accessibilityLabel?: string;
        testID?: string;
    }) => ReactMod.createElement(RNMod.View, { accessibilityLabel, testID }, children);

    const Rect = ({
        width,
        testID,
    }: {
        x?: number;
        y?: number;
        width?: number;
        height?: number;
        rx?: number;
        fill?: string;
        testID?: string;
    }) =>
        ReactMod.createElement(RNMod.View, {
            testID,
            accessibilityLabel: `rect-width-${width ?? 0}`,
            style: { width: width ?? 0, height: 12 },
        });

    const SvgText = ({ children, testID }: { children?: React.ReactNode; testID?: string }) =>
        ReactMod.createElement(RNMod.Text, { testID }, children);

    return {
        __esModule: true,
        default: Svg,
        Svg,
        Rect,
        Text: SvgText,
    };
});

jest.mock("../../src/hooks/useBootstrap", () => ({
    useBootstrap: () => ({ bootstrap: { current_user: null } }),
}));

import React from "react";
import { render, screen } from "@testing-library/react-native";
import { LegislatorChartsPanel } from "../../src/components/LegislatorChartsPanel";

const FULL_SCORE = {
    count_agreed: 10,
    count_disagreed: 4,
    count_legislator_abstained: 2,
    count_no_legislator_vote: 1,
};

const ZERO_SCORE = {
    count_agreed: 0,
    count_disagreed: 0,
    count_legislator_abstained: 0,
    count_no_legislator_vote: 0,
};

describe("LegislatorChartsPanel (Phase 35 D-03 SVG bar chart)", () => {
    test("renders 4 SVG rows with accessibilityLabel in '{label} {value}' form", () => {
        render(<LegislatorChartsPanel score={FULL_SCORE} testID="charts-panel" />);
        expect(screen.getByLabelText("Agreed 10")).toBeTruthy();
        expect(screen.getByLabelText("Disagreed 4")).toBeTruthy();
        expect(screen.getByLabelText("Legislator Abstained 2")).toBeTruthy();
        expect(screen.getByLabelText("No Legislator Vote 1")).toBeTruthy();
    });

    test("wrapper View gets the testID prop", () => {
        render(<LegislatorChartsPanel score={FULL_SCORE} testID="charts-test-id" />);
        expect(screen.getByTestId("charts-test-id")).toBeTruthy();
    });

    test("when all score values are 0, no Rect has width > 0", () => {
        render(<LegislatorChartsPanel score={ZERO_SCORE} testID="charts-zero" />);
        const nonZeroRects = screen.queryAllByLabelText(/^rect-width-[^0]/).filter((node) => {
            const match = node.props.accessibilityLabel?.match(/^rect-width-(\d+(\.\d+)?)$/);
            return match && parseFloat(match[1]) > 0;
        });
        expect(nonZeroRects.length).toBe(0);
    });

    test("renders bar testIDs following {testID}-bar-{key} pattern", () => {
        render(<LegislatorChartsPanel score={FULL_SCORE} testID="panel-42" />);
        expect(screen.getByTestId("panel-42-bar-agreed")).toBeTruthy();
        expect(screen.getByTestId("panel-42-bar-disagreed")).toBeTruthy();
        expect(screen.getByTestId("panel-42-bar-abstained")).toBeTruthy();
        expect(screen.getByTestId("panel-42-bar-no-vote")).toBeTruthy();
    });

    test("agreed bar has width > 0 when count_agreed is positive", () => {
        render(<LegislatorChartsPanel score={FULL_SCORE} testID="panel-width" />);
        const agreedBar = screen.getByTestId("panel-width-bar-agreed");
        // The fake Rect copies its width prop straight into style.width
        const width = agreedBar.props.style?.width ?? 0;
        expect(width).toBeGreaterThan(0);
    });
});

// @lat: [[voter-privacy-threshold#The mobile legislator screens draw percentages or the placeholder]]
describe("LegislatorChartsPanel for a district or locale score", () => {
    const counters = {
        count_agreed: 4321,
        count_disagreed: 1234,
        count_legislator_abstained: 0,
        count_no_legislator_vote: 0,
    };
    const shown = {
        ...counters,
        comparison_suppressed: false,
        agreed_percent: 62,
        disagreed_percent: 30,
        no_legislator_vote_percent: 8,
        legislator_abstained_percent: 0,
    };
    const hidden = {
        ...counters,
        comparison_suppressed: true,
        agreed_percent: null,
        disagreed_percent: null,
        no_legislator_vote_percent: null,
        legislator_abstained_percent: null,
    };

    test("draws an unsuppressed score from its percentages and shows no raw counter", () => {
        render(<LegislatorChartsPanel group score={shown} title="District 7" testID="district-panel" />);

        expect(screen.getByLabelText("Agreed 62 percent")).toBeTruthy();
        expect(screen.getByLabelText("Disagreed 30 percent")).toBeTruthy();
        expect(screen.getByLabelText("No Legislator Vote 8 percent")).toBeTruthy();
        expect(screen.getByText("62%")).toBeTruthy();
        expect(JSON.stringify(screen.toJSON())).not.toMatch(/4,?321|1,?234/);
    });

    test("shows 'Not enough votes yet' under the title and no chart for a suppressed score", () => {
        render(<LegislatorChartsPanel group score={hidden} title="District 7" testID="district-panel" />);

        expect(screen.getByText("District 7")).toBeTruthy();
        expect(screen.getByText("Not enough votes yet")).toBeTruthy();
        expect(screen.queryByTestId("district-panel-bar-agreed")).toBeNull();
        expect(JSON.stringify(screen.toJSON())).not.toMatch(/4,?321|1,?234|%/);
    });

    test("treats a cached score with no flag as suppressed", () => {
        render(<LegislatorChartsPanel group score={counters} testID="district-panel" />);

        expect(screen.getByText("Not enough votes yet")).toBeTruthy();
        expect(screen.queryByTestId("district-panel-bar-agreed")).toBeNull();
    });

    test("leaves the reader's own score drawn from its counters", () => {
        render(<LegislatorChartsPanel score={counters} testID="own-panel" />);

        expect(screen.getByLabelText("Agreed 4321")).toBeTruthy();
        expect(screen.queryByText("Not enough votes yet")).toBeNull();
    });
});
