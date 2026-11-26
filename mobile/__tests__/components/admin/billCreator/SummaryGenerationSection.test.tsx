import React from "react";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../../src/api/errors";

const mockApiPost = jest.fn();
const mockApiGet = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: {
        post: (...args: unknown[]) => mockApiPost(...args),
        get: (...args: unknown[]) => mockApiGet(...args),
    },
}));

jest.mock("../../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

import SummaryGenerationSection from "../../../../src/components/admin/billCreator/SummaryGenerationSection";
import SummaryTab from "../../../../src/screens/admin/billCreator/tabs/SummaryTab";

const provisioning = (overrides: Record<string, unknown> = {}) => ({
    generation_status: null,
    generation_error: null,
    llm_summary: null,
    llm_full_breakdown: null,
    llm_provider: null,
    llm_generated_at: null,
    stale: false,
    stale_change_kind: null,
    stale_change_at: null,
    reclaimable: false,
    paste_owns_summary_run: false,
    has_testimony: false,
    citations_valid: null,
    invalid_citations: null,
    ...overrides,
});

const tabData = (bill: Record<string, unknown> = {}, extra: Record<string, unknown> = {}) => ({
    bill: {
        id: 42,
        external_id: "25-0001",
        title: "A bill",
        summary: null,
        summary_ai_unreviewed: false,
        bill_llm_provisioning: provisioning(),
        bill_pipeline_refresh: null,
        bill_pipeline_last_failure: null,
        ...bill,
    },
    active_legislation_pipeline_run: null,
    ...extra,
});

const renderSection = (data: ReturnType<typeof tabData>, billId: number | null = 42) => {
    const refresh = jest.fn(async () => {});
    const view = render(<SummaryGenerationSection billId={billId} data={data} refresh={refresh} />);
    return { refresh, rerender: view.rerender };
};

// @lat: [[mobile-bill-creator#Sections#The summary generation section]]
describe("SummaryGenerationSection", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiPost.mockResolvedValue({});
        jest.useFakeTimers();
        jest.setSystemTime(new Date("2026-11-24T12:00:00Z"));
    });

    afterEach(() => {
        jest.useRealTimers();
    });

    it("renders the section from the Summary tab", () => {
        render(<SummaryTab billId={42} data={tabData()} refresh={jest.fn(async () => {})} />);

        expect(screen.getByTestId("admin-summary-generation")).toBeTruthy();
    });

    it("posts generate_summary for a row never run and refetches the tab", async () => {
        const { refresh } = renderSection(tabData());

        expect(screen.getByTestId("admin-summary-status")).toHaveTextContent("Not generated");
        fireEvent.press(screen.getByTestId("admin-summary-generate"));

        await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
        expect(mockApiPost).toHaveBeenCalledWith("/bills/42/generate_summary", {});
    });

    it("labels the button Retry after a failure and shows the reason", async () => {
        renderSection(
            tabData({
                bill_llm_provisioning: provisioning({
                    generation_status: "failed",
                    generation_error: "Model timed out",
                }),
            }),
        );

        expect(screen.getByTestId("admin-summary-status")).toHaveTextContent("Failed");
        expect(screen.getByTestId("admin-summary-failed")).toHaveTextContent(
            "Summary generation failedModel timed out",
        );
        expect(screen.getByTestId("admin-summary-generate")).toHaveTextContent("Retry");
        fireEvent.press(screen.getByTestId("admin-summary-generate"));

        await waitFor(() => expect(mockApiPost).toHaveBeenCalledWith("/bills/42/generate_summary", {}));
    });

    // @lat: [[mobile-bill-creator#Sections#The summary generation section#Polling while a summary is generated]]
    it("polls while the summary is queued and stops once it is ready", () => {
        const { refresh, rerender } = renderSection(
            tabData({ bill_llm_provisioning: provisioning({ generation_status: "pending" }) }),
        );

        expect(screen.getByTestId("admin-summary-status")).toHaveTextContent("Queued…");
        expect(screen.getByTestId("admin-summary-queued-notice")).toBeTruthy();
        expect(screen.getByTestId("admin-summary-generate")).toBeDisabled();
        jest.advanceTimersByTime(5000);
        expect(refresh).toHaveBeenCalledTimes(1);

        rerender(
            <SummaryGenerationSection
                billId={42}
                data={tabData({
                    summary: "The bill **raises** the fee.",
                    summary_ai_unreviewed: true,
                    bill_llm_provisioning: provisioning({
                        generation_status: "completed",
                        llm_summary: "The bill **raises** the fee.",
                    }),
                })}
                refresh={refresh}
            />,
        );

        expect(screen.getByTestId("admin-summary-status")).toHaveTextContent("Ready");
        expect(screen.getByTestId("admin-summary-published")).toHaveTextContent("The bill raises the fee.");
        expect(screen.getByTestId("admin-summary-ai-unreviewed")).toHaveTextContent(
            "Generated using AI, not yet reviewed by a human.",
        );
        jest.advanceTimersByTime(20000);
        expect(refresh).toHaveBeenCalledTimes(1);
    });

    it("polls a bill with no provisioning row for one minute only", () => {
        const { refresh } = renderSection(tabData({ bill_llm_provisioning: null }));

        expect(screen.getByTestId("admin-summary-no-pipeline-data")).toBeTruthy();
        act(() => {
            jest.advanceTimersByTime(60000);
        });
        const callsInTheMinute = refresh.mock.calls.length;
        expect(callsInTheMinute).toBeGreaterThanOrEqual(11);
        expect(callsInTheMinute).toBeLessThanOrEqual(12);
        act(() => {
            jest.advanceTimersByTime(30000);
        });
        expect(refresh).toHaveBeenCalledTimes(callsInTheMinute);
    });

    it("generates a bill with no provisioning row through regenerate_summary and shows a failed pipeline run", async () => {
        renderSection(
            tabData({
                bill_llm_provisioning: null,
                bill_pipeline_last_failure: {
                    run_id: 7,
                    error_message: "PDF missing",
                    failed_at: "2026-11-24T11:00:00Z",
                },
            }),
        );

        expect(screen.getByTestId("admin-summary-pipeline-failure")).toHaveTextContent(/25-0001: PDF missing/);
        fireEvent.press(screen.getByTestId("admin-summary-generate"));

        await waitFor(() => expect(mockApiPost).toHaveBeenCalledWith("/bills/42/regenerate_summary", {}));
    });

    it("shows the server's reason when the generation is refused", async () => {
        mockApiPost.mockRejectedValueOnce(
            new ApiRequestError(
                "validation_failed",
                "Validation failed.",
                { generation: "Generation already in progress" },
                422,
            ),
        );
        const { refresh } = renderSection(tabData());

        fireEvent.press(screen.getByTestId("admin-summary-generate"));

        expect(await screen.findByTestId("admin-summary-error")).toHaveTextContent("Generation already in progress");
        expect(refresh).not.toHaveBeenCalled();
    });

    it("regenerates a ready summary on the second tap", async () => {
        const { refresh } = renderSection(
            tabData({
                summary: "Published text",
                bill_llm_provisioning: provisioning({ generation_status: "completed", llm_summary: "Published text" }),
            }),
        );

        fireEvent.press(screen.getByTestId("admin-summary-regenerate"));
        expect(screen.getByTestId("admin-summary-regenerate")).toHaveTextContent("Tap again to regenerate");
        expect(mockApiPost).not.toHaveBeenCalled();
        fireEvent.press(screen.getByTestId("admin-summary-regenerate"));

        await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
        expect(mockApiPost).toHaveBeenCalledWith("/bills/42/regenerate_summary", {});
    });

    it("shows a different draft beneath the published summary and the run in flight", () => {
        renderSection(
            tabData({
                summary: "Published text",
                bill_llm_provisioning: provisioning({ generation_status: "generating", llm_summary: "Draft text" }),
            }),
        );

        expect(screen.getByTestId("admin-summary-in-flight")).toHaveTextContent(
            "A new summary is being writtenYou are looking at the draft summary on this bill. The new run replaces it when it finishes. The published summary below is not changed by a run.",
        );
        expect(screen.getByTestId("admin-summary-draft")).toHaveTextContent(/^The model wrote a different summary/);
        expect(screen.getByTestId("admin-summary-draft")).toHaveTextContent(/Draft text$/);
        expect(screen.getByTestId("admin-summary-regenerate")).toBeDisabled();
    });

    it("keeps the run buttons off while the bill's pipeline refresh is busy", () => {
        renderSection(tabData({ bill_pipeline_refresh: { status: "queued" } }));

        expect(screen.getByTestId("admin-summary-pipeline-busy")).toHaveTextContent(
            "Generation is unavailable until this pipeline run starts and finishes.",
        );
        expect(screen.getByTestId("admin-summary-generate")).toBeDisabled();
    });

    it("offers a new run on an abandoned generating row with no draft", () => {
        renderSection(
            tabData({ bill_llm_provisioning: provisioning({ generation_status: "generating", reclaimable: true }) }),
        );

        expect(screen.getByTestId("admin-summary-status")).toHaveTextContent("Abandoned");
        expect(screen.getByTestId("admin-summary-abandoned")).toHaveTextContent(
            /^This run stopped part-way, and nothing is working on it now\./,
        );
        expect(screen.getByTestId("admin-summary-generate")).toBeEnabled();
    });

    it("shows a stale summary's header and regenerates from it", async () => {
        renderSection(
            tabData({
                summary: "Published text",
                bill_llm_provisioning: provisioning({
                    generation_status: "completed",
                    llm_summary: "Published text",
                    stale: true,
                    stale_change_kind: "testimony",
                    stale_change_at: "2026-11-24T09:00:00Z",
                }),
            }),
        );

        expect(screen.getByTestId("admin-summary-stale")).toHaveTextContent(
            /^Summary is out of dateStale: testimony updated 3h ago/,
        );
        expect(screen.queryByTestId("admin-summary-regenerate")).toBeNull();
        fireEvent.press(screen.getByTestId("admin-summary-regenerate-latest"));
        fireEvent.press(screen.getByTestId("admin-summary-regenerate-latest"));

        await waitFor(() => expect(mockApiPost).toHaveBeenCalledWith("/bills/42/regenerate_summary", {}));
    });

    describe("generation options", () => {
        const modelOptions = [
            { id: "anthropic/claude-opus", label: "Claude Opus", supports_reasoning: true },
            { id: "openai/gpt-mini", label: "GPT Mini", supports_reasoning: false },
        ];
        const withOptions = (
            bill: Record<string, unknown> = {},
            standing: { model?: string | null; effort?: string | null } = {},
        ) =>
            tabData(bill, {
                summary_model_options: modelOptions,
                current_summarization_model: standing.model === undefined ? "openai/gpt-mini" : standing.model,
                current_summarization_reasoning_effort: standing.effort ?? null,
            });
        const completed = {
            summary: "Published text",
            bill_llm_provisioning: provisioning({ generation_status: "completed", llm_summary: "Published text" }),
        };

        // @lat: [[mobile-bill-creator#Sections#The summary generation section#Generation options]]
        it("sends the standing model with generate when the admin touches nothing", async () => {
            renderSection(withOptions());

            expect(screen.getByTestId("admin-summary-model-openai/gpt-mini")).toHaveProp("accessibilityState", {
                selected: true,
                disabled: false,
            });
            expect(screen.queryByTestId("admin-summary-reasoning")).toBeNull();
            fireEvent.press(screen.getByTestId("admin-summary-generate"));

            await waitFor(() =>
                expect(mockApiPost).toHaveBeenCalledWith("/bills/42/generate_summary", {
                    summarization_model: "openai/gpt-mini",
                }),
            );
        });

        it("sends the chosen model and reasoning level with generate", async () => {
            renderSection(withOptions());

            fireEvent.press(screen.getByTestId("admin-summary-model-anthropic/claude-opus"));
            fireEvent.press(screen.getByTestId("admin-summary-reasoning-high"));
            fireEvent.press(screen.getByTestId("admin-summary-generate"));

            await waitFor(() =>
                expect(mockApiPost).toHaveBeenCalledWith("/bills/42/generate_summary", {
                    summarization_model: "anthropic/claude-opus",
                    reasoning_effort: "high",
                }),
            );
        });

        it("opens on the standing reasoning level and sends default when the admin sets it back", async () => {
            renderSection(withOptions({}, { model: "anthropic/claude-opus", effort: "medium" }));

            expect(screen.getByTestId("admin-summary-reasoning-medium")).toHaveProp("accessibilityState", {
                selected: true,
                disabled: false,
            });
            fireEvent.press(screen.getByTestId("admin-summary-reasoning-default"));
            fireEvent.press(screen.getByTestId("admin-summary-generate"));

            await waitFor(() =>
                expect(mockApiPost).toHaveBeenCalledWith("/bills/42/generate_summary", {
                    summarization_model: "anthropic/claude-opus",
                    reasoning_effort: "default",
                }),
            );
        });

        it("drops the reasoning level for a model that does not reason", async () => {
            renderSection(withOptions({}, { model: "anthropic/claude-opus", effort: "high" }));

            fireEvent.press(screen.getByTestId("admin-summary-model-openai/gpt-mini"));
            expect(screen.queryByTestId("admin-summary-reasoning")).toBeNull();
            fireEvent.press(screen.getByTestId("admin-summary-generate"));

            await waitFor(() =>
                expect(mockApiPost).toHaveBeenCalledWith("/bills/42/generate_summary", {
                    summarization_model: "openai/gpt-mini",
                }),
            );
        });

        it("says the standing default runs when the standing model is not offered", () => {
            renderSection(withOptions(completed, { model: "retired/model" }));

            expect(screen.getByTestId("admin-summary-model-standing")).toHaveTextContent("Standing default");
            expect(screen.getByTestId("admin-summary-run-model")).toHaveTextContent(
                "This run uses the standing default model.",
            );
        });

        it("sends the model, reasoning level and trimmed instructions with regenerate, then clears them", async () => {
            const { refresh } = renderSection(withOptions(completed));

            fireEvent.press(screen.getByTestId("admin-summary-model-anthropic/claude-opus"));
            fireEvent.press(screen.getByTestId("admin-summary-reasoning-low"));
            fireEvent.changeText(screen.getByTestId("admin-summary-instructions"), "  Name the tax rate.\n");
            expect(screen.getByTestId("admin-summary-instructions-count")).toHaveTextContent("18 / 2,000");
            expect(screen.getByTestId("admin-summary-run-model")).toHaveTextContent("This run uses Claude Opus.");
            fireEvent.press(screen.getByTestId("admin-summary-regenerate"));
            fireEvent.press(screen.getByTestId("admin-summary-regenerate"));

            await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
            expect(mockApiPost).toHaveBeenCalledWith("/bills/42/regenerate_summary", {
                summarization_model: "anthropic/claude-opus",
                summary_instructions: "Name the tax rate.",
                reasoning_effort: "low",
            });
            expect(screen.getByTestId("admin-summary-instructions")).toHaveProp("value", "");
        });

        it("keeps the instructions when the regeneration is refused", async () => {
            mockApiPost.mockRejectedValueOnce(
                new ApiRequestError("validation_failed", "Validation failed.", { generation: "Too long" }, 422),
            );
            renderSection(withOptions(completed));

            fireEvent.changeText(screen.getByTestId("admin-summary-instructions"), "Name the tax rate.");
            fireEvent.press(screen.getByTestId("admin-summary-regenerate"));
            fireEvent.press(screen.getByTestId("admin-summary-regenerate"));

            expect(await screen.findByTestId("admin-summary-error")).toHaveTextContent("Too long");
            expect(screen.getByTestId("admin-summary-instructions")).toHaveProp("value", "Name the tax rate.");
        });

        it("refuses instructions over 2,000 code points", () => {
            renderSection(withOptions(completed));

            fireEvent.changeText(screen.getByTestId("admin-summary-instructions"), "é".repeat(2001));

            expect(screen.getByTestId("admin-summary-instructions-error")).toHaveTextContent(
                "Instructions exceed the 2,000 code point limit. Please shorten them before regenerating.",
            );
            expect(screen.getByTestId("admin-summary-regenerate")).toBeDisabled();
        });

        it("sends the instructions with Regenerate from latest data", async () => {
            renderSection(
                withOptions({
                    ...completed,
                    bill_llm_provisioning: provisioning({
                        generation_status: "completed",
                        llm_summary: "Published text",
                        stale: true,
                    }),
                }),
            );

            fireEvent.changeText(screen.getByTestId("admin-summary-instructions"), "Name the tax rate.");
            fireEvent.press(screen.getByTestId("admin-summary-regenerate-latest"));
            fireEvent.press(screen.getByTestId("admin-summary-regenerate-latest"));

            await waitFor(() =>
                expect(mockApiPost).toHaveBeenCalledWith("/bills/42/regenerate_summary", {
                    summarization_model: "openai/gpt-mini",
                    summary_instructions: "Name the tax rate.",
                }),
            );
        });

        it("sends only the chosen reasoning level from a bill with no provisioning row", async () => {
            renderSection(
                withOptions({ bill_llm_provisioning: null }, { model: "anthropic/claude-opus", effort: "high" }),
            );

            fireEvent.press(screen.getByTestId("admin-summary-reasoning-default"));
            fireEvent.press(screen.getByTestId("admin-summary-generate"));

            await waitFor(() =>
                expect(mockApiPost).toHaveBeenCalledWith("/bills/42/regenerate_summary", {
                    summarization_model: "anthropic/claude-opus",
                }),
            );
            expect(screen.queryByTestId("admin-summary-instructions")).toBeNull();
        });
    });

    describe("Prepare prompt", () => {
        const noRow = (refreshStatus: string | null = null) =>
            tabData({
                bill_llm_provisioning: null,
                bill_pipeline_refresh: refreshStatus === null ? null : { status: refreshStatus },
            });

        it("points the admin to Paste summary JSON for the agent's reply", async () => {
            mockApiGet.mockResolvedValueOnce({ summary_prompt: "Summarize bill 25-0001.", bill: {} });
            renderSection(noRow());

            fireEvent.press(screen.getByTestId("admin-summary-prepare-prompt"));

            expect(await screen.findByTestId("admin-summary-prompt-paste-destination")).toHaveTextContent(
                "When the agent replies, close this prompt and use Paste summary JSON below. No generation is needed, and pasting costs nothing.",
            );
        });

        // @lat: [[mobile-bill-creator#Sections#The summary generation section#Preparing the summary prompt]]
        it("asks the server for the prompt and shows its text", async () => {
            mockApiGet.mockResolvedValueOnce({ summary_prompt: "Summarize bill 25-0001.", bill: {} });
            renderSection(noRow());

            fireEvent.press(screen.getByTestId("admin-summary-prepare-prompt"));

            expect(await screen.findByTestId("admin-summary-prompt-text")).toHaveTextContent("Summarize bill 25-0001.");
            expect(mockApiGet).toHaveBeenCalledWith("/admin/bill_creator/42/summary?summary_prompt=1");
            expect(screen.getByTestId("admin-summary-prompt")).toHaveTextContent(/^Bill summary prompt/);
            expect(screen.queryByTestId("admin-summary-prompt-stale")).toBeNull();
            fireEvent.press(screen.getByTestId("admin-summary-prompt-close"));
            expect(screen.queryByTestId("admin-summary-prompt")).toBeNull();
        });

        it("marks the prompt out of date once the pipeline changes the bill and prepares it again", async () => {
            mockApiGet.mockResolvedValueOnce({ summary_prompt: "First prompt", bill: { bill_pipeline_refresh: null } });
            const { refresh, rerender } = renderSection(noRow());

            fireEvent.press(screen.getByTestId("admin-summary-prepare-prompt"));
            await screen.findByTestId("admin-summary-prompt-text");
            rerender(<SummaryGenerationSection billId={42} data={noRow("running")} refresh={refresh} />);

            expect(screen.getByTestId("admin-summary-prompt-stale")).toHaveTextContent(
                "This prompt is out of dateThe pipeline changed this bill after the prompt was prepared, so the text below describes an earlier version. Prepare it again before you copy it.",
            );
            mockApiGet.mockResolvedValueOnce({
                summary_prompt: "Second prompt",
                bill: { bill_pipeline_refresh: { status: "running" } },
            });
            fireEvent.press(screen.getByTestId("admin-summary-prompt-reprepare"));

            await waitFor(() =>
                expect(screen.getByTestId("admin-summary-prompt-text")).toHaveTextContent("Second prompt"),
            );
            expect(screen.queryByTestId("admin-summary-prompt-stale")).toBeNull();
        });

        it("says so when the prompt cannot be built", async () => {
            mockApiGet.mockRejectedValueOnce(new Error("boom"));
            renderSection(noRow());

            fireEvent.press(screen.getByTestId("admin-summary-prepare-prompt"));

            expect(await screen.findByTestId("admin-summary-prompt-error")).toHaveTextContent(
                "Could not build the prompt — try again.",
            );
            expect(screen.queryByTestId("admin-summary-prompt")).toBeNull();
        });
    });

    it("shows the breakdown behind a toggle", () => {
        renderSection(
            tabData({
                summary: "Published text",
                bill_llm_provisioning: provisioning({
                    generation_status: "completed",
                    llm_summary: "Published text",
                    llm_full_breakdown: "Section 1 changes the fee.",
                }),
            }),
        );

        expect(screen.queryByTestId("admin-summary-breakdown")).toBeNull();
        fireEvent.press(screen.getByTestId("admin-summary-breakdown-toggle"));
        expect(screen.getByTestId("admin-summary-breakdown")).toHaveTextContent("Section 1 changes the fee.");
    });
});
