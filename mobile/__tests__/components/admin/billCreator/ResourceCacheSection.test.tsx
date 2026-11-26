import React from "react";
import { fireEvent, render, screen } from "@testing-library/react-native";

jest.mock("../../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

import ResourceCacheSection, {
    type ResourceCacheRow,
} from "../../../../src/components/admin/billCreator/ResourceCacheSection";

const mirrors: ResourceCacheRow[] = [
    {
        tier: "pdf",
        last_generated_at: "2026-11-24T11:00:00Z",
        version_id: "v3",
        stale: false,
        source_artifact_id: null,
    },
    {
        tier: "diff",
        last_generated_at: "2026-11-22T12:00:00Z",
        version_id: null,
        stale: true,
        source_artifact_id: null,
    },
];

const open = () => fireEvent.press(screen.getByTestId("admin-resource-cache-toggle"));

// @lat: [[mobile-bill-creator#Sections#The pipeline read-only panels]]
describe("ResourceCacheSection", () => {
    beforeEach(() => {
        jest.useFakeTimers();
        jest.setSystemTime(new Date("2026-11-24T12:00:00Z"));
    });

    afterEach(() => jest.useRealTimers());

    it("starts collapsed", () => {
        render(<ResourceCacheSection mirrors={mirrors} />);

        expect(screen.queryByTestId("admin-resource-cache-tier-pdf")).toBeNull();
    });

    it("shows a row per tier in the web's order with version and freshness", () => {
        render(<ResourceCacheSection mirrors={mirrors} />);
        open();

        expect(screen.getByTestId("admin-resource-cache-tier-pdf")).toHaveTextContent(/PDF/);
        expect(screen.getByTestId("admin-resource-cache-tier-pdf")).toHaveTextContent(/1h ago/);
        expect(screen.getByTestId("admin-resource-cache-tier-pdf")).toHaveTextContent(/v3/);
        expect(screen.getByTestId("admin-resource-cache-tier-pdf")).toHaveTextContent(/Fresh/);
        expect(screen.getByTestId("admin-resource-cache-tier-diff")).toHaveTextContent(/2d ago/);
        expect(screen.getByTestId("admin-resource-cache-tier-diff")).toHaveTextContent(/Stale/);
        expect(screen.getByTestId("admin-resource-cache-tier-diff")).toHaveTextContent(/Version —/);
        expect(screen.getByTestId("admin-resource-cache-tier-summary")).toHaveTextContent(/Not cached/);
    });

    it("reads Not cached on every tier when there are no mirrors", () => {
        render(<ResourceCacheSection mirrors={[]} />);
        open();

        for (const [tier, label] of [
            ["pdf", "PDF"],
            ["extracted_text", "Extracted Text"],
            ["parsed_sections", "Parsed Sections"],
            ["diff", "Diff"],
            ["summary", "Summary"],
        ]) {
            expect(screen.getByTestId(`admin-resource-cache-tier-${tier}`)).toHaveTextContent(new RegExp(label));
            expect(screen.getByTestId(`admin-resource-cache-tier-${tier}`)).toHaveTextContent(/Not cached/);
        }
    });
});
