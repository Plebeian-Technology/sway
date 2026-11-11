// @lat: [[user-vote-submission#Mobile vote controls]]
const mockImpactAsync = jest.fn(async () => {});
jest.mock("expo-haptics", () => ({
    impactAsync: mockImpactAsync,
    ImpactFeedbackStyle: { Light: "Light", Medium: "Medium", Heavy: "Heavy" },
}));

let mockAuthenticated = true;
jest.mock("../src/hooks/useSession", () => ({
    useSession: () => ({ isAuthenticated: mockAuthenticated, loading: false }),
}));

// @lat: [[user-vote-submission#Mobile vote controls]]
let mockNeedsUpdate = true;
jest.mock("../src/state/BootstrapContext", () => ({
    useBootstrap: () => ({
        bootstrap: null,
        loading: false,
        error: null,
        refetch: jest.fn(),
        needsUpdate: mockNeedsUpdate,
    }),
}));
jest.mock("lucide-react-native", () => {
    /* oxlint-disable @typescript-eslint/no-require-imports */
    const ReactMod = require("react");
    const RNMod = require("react-native");
    /* oxlint-enable @typescript-eslint/no-require-imports */
    return {
        X: function XStub() {
            return ReactMod.createElement(RNMod.View, { testID: "lucide-x" });
        },
        WifiOff: function WifiOffStub() {
            return ReactMod.createElement(RNMod.View, { testID: "lucide-wifioff" });
        },
    };
});

import React from "react";
import { render, screen } from "@testing-library/react-native";
import * as fs from "fs";
import * as path from "path";

import { VoteButton } from "../src/components/VoteButton";
import { SkeletonCard } from "../src/components/SkeletonCard";
import { UpdateBanner } from "../src/components/UpdateBanner";
import { OfflineBanner } from "../src/components/OfflineBanner";

describe("a11y audit (read-only — does NOT modify component files)", () => {
    beforeEach(() => {
        mockAuthenticated = true;
        mockNeedsUpdate = true;
    });

    test("VoteButton has accessibilityRole=button and a 'Vote for {bill}' label", () => {
        render(<VoteButton userVote={null} onPress={() => {}} billTitle="HB 42" label="For" />);
        const btn = screen.getByLabelText(/vote for HB 42/i);
        expect(btn.props.accessibilityRole).toBe("button");
    });

    test("VoteButton (Against) has accessibilityRole=button and a 'Vote against {bill}' label", () => {
        render(<VoteButton userVote={null} onPress={() => {}} billTitle="HB 42" label="Against" />);
        const btn = screen.getByLabelText(/vote against HB 42/i);
        expect(btn.props.accessibilityRole).toBe("button");
    });

    test("SkeletonCard has accessibilityLabel='Loading'", () => {
        render(<SkeletonCard />);
        expect(screen.getByLabelText("Loading")).toBeTruthy();
    });

    test("UpdateBanner exposes 'Dismiss update banner' a11y label when shown", () => {
        render(<UpdateBanner />);
        expect(screen.getByLabelText("Dismiss update banner")).toBeTruthy();
    });

    test("OfflineBanner has accessibilityRole='alert'", () => {
        render(<OfflineBanner />);
        // @lat: [[user-vote-submission#Mobile vote controls]]
        const node = screen.getByTestId("offline-banner");
        expect(node.props.accessibilityRole).toBe("alert");
    });

    test("No source file in mobile/src sets allowFontScaling={false} (D-44 BLOCKER gate)", () => {
        const root = path.join(__dirname, "..", "src");
        const walk = (d: string): string[] =>
            fs.readdirSync(d).flatMap((entry: string) => {
                const p = path.join(d, entry);
                return fs.statSync(p).isDirectory() ? walk(p) : [p];
            });
        const offenders = walk(root)
            .filter((p: string) => /\.(ts|tsx)$/.test(p))
            .filter((p: string) => fs.readFileSync(p, "utf8").includes("allowFontScaling={false}"));
        expect(offenders).toEqual([]);
    });
});
