import React from "react";
import { fireEvent, render, screen } from "@testing-library/react-native";

jest.mock("../../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

import RunSelectorSection, {
    type RecentPipelineRun,
} from "../../../../src/components/admin/billCreator/RunSelectorSection";

const runs: RecentPipelineRun[] = [
    {
        id: 12,
        status: "failed",
        kind: "single",
        bill_external_id: "25-0001",
        created_at: "2026-11-24T10:00:00Z",
        completed_at: "2026-11-24T11:30:00Z",
    },
    {
        id: 11,
        status: "succeeded",
        kind: "all_bills",
        bill_external_id: null,
        created_at: "2026-11-23T10:00:00Z",
        completed_at: null,
    },
];

// @lat: [[mobile-bill-creator#Sections#The run selector section]]
describe("RunSelectorSection", () => {
    beforeEach(() => {
        jest.useFakeTimers();
        jest.setSystemTime(new Date("2026-11-24T12:00:00Z"));
    });

    afterEach(() => jest.useRealTimers());

    it("shows nothing when there are no runs", () => {
        const { toJSON } = render(
            <RunSelectorSection runs={[]} currentRunId={null} pinned={false} onPick={jest.fn()} />,
        );
        expect(toJSON()).toBeNull();
    });

    it("reads Latest run (auto) until a run is pinned", () => {
        render(<RunSelectorSection runs={runs} currentRunId={12} pinned={false} onPick={jest.fn()} />);

        expect(screen.getByTestId("admin-run-selector-current")).toHaveTextContent("Latest run (auto)");
    });

    it("names the pinned run by id, status, scope and start", () => {
        render(<RunSelectorSection runs={runs} currentRunId={12} pinned onPick={jest.fn()} />);

        expect(screen.getByTestId("admin-run-selector-current")).toHaveTextContent(
            /^Run #12 · ✗ failed 30m ago · 25-0001 · November 24, 2026 at /,
        );
    });

    it("lists the runs and picks one, then returns to the latest run", () => {
        const onPick = jest.fn();
        render(<RunSelectorSection runs={runs} currentRunId={12} pinned={false} onPick={onPick} />);

        expect(screen.queryByTestId("admin-run-selector-option-11")).toBeNull();
        fireEvent.press(screen.getByTestId("admin-run-selector-toggle"));
        expect(screen.getByTestId("admin-run-selector-option-11")).toHaveTextContent(
            /^Run #11 · ✓ succeeded · all bills · /,
        );

        fireEvent.press(screen.getByTestId("admin-run-selector-option-11"));
        expect(onPick).toHaveBeenCalledWith(11);
        expect(screen.queryByTestId("admin-run-selector-option-11")).toBeNull();

        fireEvent.press(screen.getByTestId("admin-run-selector-toggle"));
        fireEvent.press(screen.getByTestId("admin-run-selector-option-latest"));
        expect(onPick).toHaveBeenLastCalledWith(null);
    });
});
