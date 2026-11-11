import { render, screen, fireEvent } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import PipelineStageSelector from "app/frontend/components/admin/creator/pipeline-controls/PipelineStageSelector";
import type { IPipelinePreview } from "app/frontend/components/admin/creator/pipeline-controls/types";

function defaultProps(
    overrides: Partial<React.ComponentProps<typeof PipelineStageSelector>> = {},
): React.ComponentProps<typeof PipelineStageSelector> {
    return {
        selectedStages: [
            "fetch-bills",
            "fetch-law",
            "extract-text",
            "parse-sections",
            "generate-diffs",
            "summarize-bill",
        ],
        isRunning: false,
        pipelinePreview: null,
        downloadMissingAssets: true,
        onToggleStage: vi.fn<(key: string) => void>(),
        onSetStages: vi.fn<(next: string[]) => void>(),
        onDownloadMissingAssetsChange: vi.fn<(next: boolean) => void>(),
        ...overrides,
    };
}

/** Every stage key, in the order the card draws them. */
const ALL_KEYS = [
    "fetch-bills",
    "fetch-law",
    "extract-text",
    "parse-sections",
    "generate-diffs",
    "fetch-hearings",
    "clean-testimony",
    "summarize-bill",
];

describe("PipelineStageSelector", () => {
    it("renders 8 stage rows in DAG order (ST-01 + ST-02 land)", () => {
        render(<PipelineStageSelector {...defaultProps()} />);
        const checkboxes = [
            "checkbox-stage-fetch-bills",
            "checkbox-stage-fetch-law",
            "checkbox-stage-extract-text",
            "checkbox-stage-parse-sections",
            "checkbox-stage-generate-diffs",
            "checkbox-stage-fetch-hearings",
            "checkbox-stage-clean-testimony",
            "checkbox-stage-summarize-bill",
        ];
        checkboxes.forEach((id) => {
            expect(screen.getByTestId(id)).toBeTruthy();
        });
    });

    it("renders fetch-law and summarize-bill as default-checked when selectedStages includes them", () => {
        render(
            <PipelineStageSelector
                {...defaultProps({
                    selectedStages: [
                        "fetch-bills",
                        "fetch-law",
                        "extract-text",
                        "parse-sections",
                        "generate-diffs",
                        "fetch-hearings",
                        "clean-testimony",
                        "summarize-bill",
                    ],
                })}
            />,
        );
        expect(screen.getByTestId("checkbox-stage-fetch-law").getAttribute("data-state")).toBe("checked");
        expect(screen.getByTestId("checkbox-stage-summarize-bill").getAttribute("data-state")).toBe("checked");
    });

    it("renders the download_missing_assets toggle with default-checked state (TG-01)", () => {
        render(<PipelineStageSelector {...defaultProps()} />);
        const toggle = screen.getByTestId("checkbox-download-missing-assets");
        expect(toggle).toBeTruthy();
        expect(toggle.getAttribute("data-state")).toBe("checked");
    });

    it("disables the toggle when both Fetch-bills AND Fetch-hearings are checked", () => {
        render(
            <PipelineStageSelector
                {...defaultProps({
                    selectedStages: ["fetch-bills", "fetch-hearings"],
                })}
            />,
        );
        const toggle = screen.getByTestId("checkbox-download-missing-assets");
        expect(toggle.hasAttribute("disabled") || toggle.getAttribute("data-disabled") !== null).toBe(true);
    });

    it("enables the toggle when only one of the fetches is checked", () => {
        render(
            <PipelineStageSelector
                {...defaultProps({
                    selectedStages: ["fetch-bills", "extract-text"],
                })}
            />,
        );
        const toggle = screen.getByTestId("checkbox-download-missing-assets");
        // disabled attribute should be absent (or false)
        expect(toggle.hasAttribute("disabled")).toBe(false);
    });

    it("disables the toggle when isRunning=true (regardless of stage selection)", () => {
        render(
            <PipelineStageSelector
                {...defaultProps({
                    isRunning: true,
                    selectedStages: ["fetch-bills"],
                })}
            />,
        );
        const toggle = screen.getByTestId("checkbox-download-missing-assets");
        expect(toggle.hasAttribute("disabled") || toggle.getAttribute("data-disabled") !== null).toBe(true);
    });

    it("renders the disabled-state subtext when both fetches are checked", () => {
        render(
            <PipelineStageSelector
                {...defaultProps({
                    selectedStages: ["fetch-bills", "fetch-hearings"],
                })}
            />,
        );
        expect(screen.getByText(/Both fetch stages are checked — there is nothing to backfill\./)).toBeTruthy();
    });

    it("renders the default subtext when the toggle is enabled", () => {
        render(<PipelineStageSelector {...defaultProps()} />);
        expect(screen.getByText(/Auto-runs upstream stages for any bills missing required data/)).toBeTruthy();
    });

    it("renders the WA-01 warn alert when dma=false AND prereq_violations present AND !isRunning", () => {
        const preview: IPipelinePreview = {
            stages_requested: ["parse-sections"],
            stages_will_run: ["parse-sections"],
            stages_auto_included: [],
            confirmation_required: false,
            confirmation_message: null,
            prereq_violations: [
                {
                    stage: "parse-sections",
                    missing_artifact: "extracted_text",
                    bill_count: 12,
                    prerequisite: "extract-text",
                },
            ],
        };
        render(
            <PipelineStageSelector
                {...defaultProps({
                    downloadMissingAssets: false,
                    pipelinePreview: preview,
                })}
            />,
        );
        const alert = screen.getByTestId("pipeline-prereq-warn-alert");
        expect(alert).toBeTruthy();
        // The agreed wording, word for word
        expect(alert.textContent).toMatch(/12 bills will FAIL Parse sections because they have no extracted_text/);
        expect(alert.textContent).toMatch(/enable Download missing assets or check Extract text/);
    });

    it("hides the WA-01 alert when downloadMissingAssets=true", () => {
        const preview: IPipelinePreview = {
            stages_requested: ["parse-sections"],
            stages_will_run: ["parse-sections"],
            stages_auto_included: [],
            confirmation_required: false,
            confirmation_message: null,
            prereq_violations: [
                {
                    stage: "parse-sections",
                    missing_artifact: "extracted_text",
                    bill_count: 12,
                    prerequisite: "extract-text",
                },
            ],
        };
        render(
            <PipelineStageSelector
                {...defaultProps({
                    downloadMissingAssets: true,
                    pipelinePreview: preview,
                })}
            />,
        );
        expect(screen.queryByTestId("pipeline-prereq-warn-alert")).toBeNull();
    });

    it("hides the WA-01 alert when prereq_violations is empty", () => {
        const preview: IPipelinePreview = {
            stages_requested: ["parse-sections"],
            stages_will_run: ["parse-sections"],
            stages_auto_included: [],
            confirmation_required: false,
            confirmation_message: null,
            prereq_violations: [],
        };
        render(
            <PipelineStageSelector
                {...defaultProps({
                    downloadMissingAssets: false,
                    pipelinePreview: preview,
                })}
            />,
        );
        expect(screen.queryByTestId("pipeline-prereq-warn-alert")).toBeNull();
    });

    it("hides the WA-01 alert when the run is in flight", () => {
        const preview: IPipelinePreview = {
            stages_requested: ["parse-sections"],
            stages_will_run: ["parse-sections"],
            stages_auto_included: [],
            confirmation_required: false,
            confirmation_message: null,
            prereq_violations: [
                {
                    stage: "parse-sections",
                    missing_artifact: "extracted_text",
                    bill_count: 12,
                    prerequisite: "extract-text",
                },
            ],
        };
        render(
            <PipelineStageSelector
                {...defaultProps({
                    isRunning: true,
                    downloadMissingAssets: false,
                    pipelinePreview: preview,
                })}
            />,
        );
        expect(screen.queryByTestId("pipeline-prereq-warn-alert")).toBeNull();
    });

    it("does NOT render the legacy 'Pull fresh data from Legistar' checkbox (RM-01)", () => {
        render(<PipelineStageSelector {...defaultProps()} />);
        expect(screen.queryByTestId("checkbox-pipeline-refresh")).toBeNull();
    });

    it("invokes onDownloadMissingAssetsChange when the toggle is clicked", () => {
        const handler = vi.fn<(next: boolean) => void>();
        render(
            <PipelineStageSelector
                {...defaultProps({
                    onDownloadMissingAssetsChange: handler,
                })}
            />,
        );
        fireEvent.click(screen.getByTestId("checkbox-download-missing-assets"));
        expect(handler).toHaveBeenCalled();
    });

    // @lat: [[pipeline-stage-auto-include-reduced-work#Why the auto-included stage chips are comma-separated with a screen-reader-only comma]]
    describe("auto-include closure list", () => {
        const previewWithAutoIncluded = (stages: string[]): IPipelinePreview => ({
            stages_requested: ["summarize-bill"],
            stages_will_run: [...stages, "summarize-bill"],
            stages_auto_included: stages,
            confirmation_required: true,
            confirmation_message: `Selected stages require: ${stages.join(", ")} — these will run too. Continue?`,
        });

        it("interleaves commas between chip display names for screen-reader / clipboard parity", () => {
            render(
                <PipelineStageSelector
                    {...defaultProps({
                        pipelinePreview: previewWithAutoIncluded(["fetch-law", "extract-text", "parse-sections"]),
                    })}
                />,
            );
            const alert = screen.getByTestId("pipeline-auto-include-alert");
            // The plain text is what a screen reader reads and what copy-paste
            // picks up, so it has to come out as a separated list rather than
            // one run-together blob.
            expect(alert.textContent).toContain("Fetch law, Extract text, Parse sections");
            // This check guards against sliding back to the run-together
            // version.
            expect(alert.textContent).not.toContain("Fetch lawExtract text");
        });

        it("omits the comma for a single auto-included chip", () => {
            render(
                <PipelineStageSelector
                    {...defaultProps({
                        pipelinePreview: previewWithAutoIncluded(["fetch-law"]),
                    })}
                />,
            );
            const alert = screen.getByTestId("pipeline-auto-include-alert");
            expect(alert.textContent).toContain("Fetch law");
            // One chip on its own must not leave a comma at the start or the
            // end of the text.
            expect(alert.textContent).not.toMatch(/Fetch law,|, Fetch law/);
        });
    });

    // @lat: [[bill-creator-pipeline-controls-panel#BillCreatorPipelineControls mechanics#Why stage selection uses two buttons rather than a tick-all box#An auto-included stage does less than the same stage ticked]]
    describe("the reduced-form note on auto-included stages", () => {
        // Its own copy rather than the one in the auto-include block below,
        // which is scoped to that describe.
        const previewWithAutoIncluded = (stages: string[]): IPipelinePreview => ({
            stages_requested: ["summarize-bill"],
            stages_will_run: [...stages, "summarize-bill"],
            stages_auto_included: stages,
            confirmation_required: true,
            confirmation_message: null,
        });

        it("names the added stages that will do less, and says what to do about it", () => {
            render(
                <PipelineStageSelector
                    {...defaultProps({
                        pipelinePreview: previewWithAutoIncluded(["extract-text"]),
                    })}
                />,
            );

            const note = screen.getByTestId("pipeline-auto-include-reduced-note");
            expect(note.textContent).toContain("Extract text");
            expect(note.textContent).toContain("reduced form");
            expect(note.textContent).toContain("Tick a stage yourself to run it in full.");
        });

        // @lat: [[bill-creator-pipeline-controls-panel#BillCreatorPipelineControls mechanics#Why stage selection uses two buttons rather than a tick-all box#An auto-included stage does less than the same stage ticked]]
        it("says outright that an added Fetch bills will not look for new bills", () => {
            render(
                <PipelineStageSelector
                    {...defaultProps({
                        pipelinePreview: previewWithAutoIncluded(["fetch-bills", "extract-text"]),
                    })}
                />,
            );

            const note = screen.getByTestId("pipeline-auto-include-reduced-note").textContent;
            expect(note).toContain("Fetch bills will not look for new bills in Legistar.");
            expect(note).toContain("asks for a bill in this run by name only when that bill has nothing saved yet");
        });

        it("leaves out the Legistar sentence when Fetch bills is not one of them", () => {
            render(
                <PipelineStageSelector
                    {...defaultProps({
                        pipelinePreview: previewWithAutoIncluded(["parse-sections"]),
                    })}
                />,
            );

            expect(screen.getByTestId("pipeline-auto-include-reduced-note").textContent).not.toContain("Legistar");
        });

        // THE ONE THAT STOPS THE NOTE LYING. fetch-law takes no mode and has no
        // per-bill loop, so it does identical work chosen or added. A blanket
        // sentence over every auto-included stage would tell the operator their
        // law fetch had been cut down when it had not.
        it("shows no note when the only added stage is one that is not reduced", () => {
            render(
                <PipelineStageSelector
                    {...defaultProps({
                        pipelinePreview: previewWithAutoIncluded(["fetch-law"]),
                    })}
                />,
            );

            expect(screen.getByTestId("pipeline-auto-include-alert")).toBeTruthy();
            expect(screen.queryByTestId("pipeline-auto-include-reduced-note")).toBeNull();
        });

        it("names only the reduced stages when a not-reduced one is added alongside", () => {
            render(
                <PipelineStageSelector
                    {...defaultProps({
                        pipelinePreview: previewWithAutoIncluded(["fetch-law", "extract-text"]),
                    })}
                />,
            );

            const note = screen.getByTestId("pipeline-auto-include-reduced-note");
            expect(note.textContent).toContain("Extract text");
            expect(note.textContent).not.toContain("Fetch law");
        });
    });

    // @lat: [[bill-creator-pipeline-controls-panel#BillCreatorPipelineControls mechanics#Why stage selection uses two buttons rather than a tick-all box]]
    describe("select all and clear all", () => {
        it("sends every stage in ONE call, not one call per stage", () => {
            const onSetStages = vi.fn<(next: string[]) => void>();
            const onToggleStage = vi.fn<(key: string) => void>();
            render(<PipelineStageSelector {...defaultProps({ selectedStages: [], onSetStages, onToggleStage })} />);

            fireEvent.click(screen.getByTestId("select-all-stages"));

            expect(onSetStages).toHaveBeenCalledTimes(1);
            expect(onSetStages).toHaveBeenCalledWith(ALL_KEYS);
            expect(onToggleStage).not.toHaveBeenCalled();
        });

        it("clears every stage in one call", () => {
            const onSetStages = vi.fn<(next: string[]) => void>();
            const onToggleStage = vi.fn<(key: string) => void>();
            render(
                <PipelineStageSelector {...defaultProps({ selectedStages: ALL_KEYS, onSetStages, onToggleStage })} />,
            );

            fireEvent.click(screen.getByTestId("clear-all-stages"));

            expect(onSetStages).toHaveBeenCalledTimes(1);
            expect(onSetStages).toHaveBeenCalledWith([]);
            expect(onToggleStage).not.toHaveBeenCalled();
        });

        // The three states, read off the two buttons. This is what a single
        // two-state tick-all box could not express without lying in the middle.
        it.each([
            ["none selected", [] as string[], { selectAll: false, clearAll: true }],
            ["some selected", ["fetch-bills"], { selectAll: false, clearAll: false }],
            ["all selected", ALL_KEYS, { selectAll: true, clearAll: false }],
        ])("with %s, greys out only the button that would do nothing", (_name, selectedStages, expected) => {
            render(<PipelineStageSelector {...defaultProps({ selectedStages })} />);

            expect((screen.getByTestId("select-all-stages") as HTMLButtonElement).disabled).toBe(expected.selectAll);
            expect((screen.getByTestId("clear-all-stages") as HTMLButtonElement).disabled).toBe(expected.clearAll);
        });

        it("says how many of the eight are selected", () => {
            render(<PipelineStageSelector {...defaultProps({ selectedStages: ["fetch-bills", "fetch-law"] })} />);

            expect(screen.getByTestId("stage-selection-count").textContent).toBe("2 of 8 selected");
        });

        // A stale key left in the address must not be counted as a stage. Six
        // real stages plus one invented one is six, not eight — otherwise the
        // count reads "7 of 8" and Select all greys out with a box unticked.
        it("counts only real stages, ignoring an unknown key", () => {
            const withStrayKey = [...ALL_KEYS.slice(0, 6), "not-a-stage"];
            render(<PipelineStageSelector {...defaultProps({ selectedStages: withStrayKey })} />);

            expect(screen.getByTestId("stage-selection-count").textContent).toBe("6 of 8 selected");
            expect((screen.getByTestId("select-all-stages") as HTMLButtonElement).disabled).toBe(false);
        });

        it("stays clickable during a run, muted like the per-stage checkboxes", () => {
            render(<PipelineStageSelector {...defaultProps({ selectedStages: ["fetch-bills"], isRunning: true })} />);

            expect((screen.getByTestId("select-all-stages") as HTMLButtonElement).disabled).toBe(false);
            expect((screen.getByTestId("clear-all-stages") as HTMLButtonElement).disabled).toBe(false);
        });

        it("still greys out select-all/clear-all by selection state during a run", () => {
            const { rerender } = render(
                <PipelineStageSelector {...defaultProps({ selectedStages: [], isRunning: true })} />,
            );

            expect((screen.getByTestId("select-all-stages") as HTMLButtonElement).disabled).toBe(false);
            expect((screen.getByTestId("clear-all-stages") as HTMLButtonElement).disabled).toBe(true);

            rerender(<PipelineStageSelector {...defaultProps({ selectedStages: ALL_KEYS, isRunning: true })} />);

            expect((screen.getByTestId("select-all-stages") as HTMLButtonElement).disabled).toBe(true);
            expect((screen.getByTestId("clear-all-stages") as HTMLButtonElement).disabled).toBe(false);
        });

        it("invokes onSetStages for select-all/clear-all clicked mid-run", () => {
            const onSetStages = vi.fn<(next: string[]) => void>();
            render(
                <PipelineStageSelector
                    {...defaultProps({ selectedStages: ["fetch-bills"], isRunning: true, onSetStages })}
                />,
            );

            fireEvent.click(screen.getByTestId("clear-all-stages"));

            expect(onSetStages).toHaveBeenCalledWith([]);
        });
    });

    describe("in-progress state", () => {
        it("keeps stage checkboxes clickable while a run is going", () => {
            render(<PipelineStageSelector {...defaultProps({ selectedStages: ["fetch-bills"], isRunning: true })} />);

            expect(screen.getByTestId("checkbox-stage-fetch-bills")).toBeEnabled();
            expect(screen.getByTestId("checkbox-stage-fetch-law")).toBeEnabled();
        });

        it("invokes onToggleStage for a stage checkbox clicked mid-run", () => {
            const onToggleStage = vi.fn<(key: string) => void>();
            render(<PipelineStageSelector {...defaultProps({ isRunning: true, onToggleStage })} />);

            fireEvent.click(screen.getByTestId("checkbox-stage-fetch-law"));

            expect(onToggleStage).toHaveBeenCalledWith("fetch-law");
        });

        it("mutes stage rows with a visible class while a run is going", () => {
            render(<PipelineStageSelector {...defaultProps({ isRunning: true })} />);

            expect(screen.getByTestId("checkbox-stage-fetch-bills").closest("li")).toHaveClass("opacity-60");
        });

        it("leaves stage rows unmuted when idle", () => {
            render(<PipelineStageSelector {...defaultProps({ isRunning: false })} />);

            expect(screen.getByTestId("checkbox-stage-fetch-bills").closest("li")).not.toHaveClass("opacity-60");
        });

        it("marks the stage list aria-busy while a run is going", () => {
            render(<PipelineStageSelector {...defaultProps({ isRunning: true })} />);

            expect(screen.getByTestId("checkbox-stage-fetch-bills").closest("ul")).toHaveAttribute("aria-busy", "true");
        });

        it("carries no aria-busy attribute on the stage list when idle", () => {
            render(<PipelineStageSelector {...defaultProps({ isRunning: false })} />);

            expect(screen.getByTestId("checkbox-stage-fetch-bills").closest("ul")).not.toHaveAttribute("aria-busy");
        });
    });
});
