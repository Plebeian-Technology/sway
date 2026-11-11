import { router } from "@inertiajs/react";
import { useCallback, useState } from "react";
import { notifyServerRefusal } from "app/frontend/components/admin/creator/notifyServerRefusal";
import type { useConfirm } from "app/frontend/components/ui/confirm-dialog";
import type { ILegislationPipelineRun } from "app/frontend/components/admin/creator/pipeline-controls/types";

interface IUsePipelineRunActions {
    run: ILegislationPipelineRun | null;
    selectedStages: string[];
    pickedBillId: string;
    swayLocaleId?: number | null;
    downloadMissingAssets: boolean;
    staleCount: number;
    orphanCount: number;
    confirm: ReturnType<typeof useConfirm>;
}

export interface PipelineRunActions {
    isPosting: boolean;
    handleResume: () => void;
    handleRestart: () => void;
    handleRun: () => void;
    handleSweepStale: () => Promise<void>;
    handleDeleteOrphans: () => Promise<void>;
}

// @lat: [[notify-server-refusal-pattern#Why serverRefusalMessage checks the shape carefully]]
const postOptions = (setIsPosting: (v: boolean) => void, fallback: string) => ({
    preserveScroll: true,
    onStart: () => setIsPosting(true),
    onFinish: () => setIsPosting(false),
    onError: (errors: unknown) => notifyServerRefusal(errors, "pipeline", fallback),
});

// @lat: [[bill-creator-pipeline-controls-panel#usePipelineRunActions notes]]
export const usePipelineRunActions = ({
    run,
    selectedStages,
    pickedBillId,
    swayLocaleId,
    downloadMissingAssets,
    staleCount,
    orphanCount,
    confirm,
}: IUsePipelineRunActions): PipelineRunActions => {
    const [isPosting, setIsPosting] = useState<boolean>(false);

    // @lat: [[bill-creator-pipeline-controls-panel#usePipelineRunActions notes]]
    const handleResume = useCallback(() => {
        if (!run) return;
        router.post(
            `/bills/legislation_pipeline_runs/${run.id}/resume`,
            {},
            postOptions(setIsPosting, "Could not resume the pipeline run."),
        );
    }, [run]);

    // @lat: [[bill-creator-pipeline-controls-panel#usePipelineRunActions notes]]
    const handleRestart = useCallback(() => {
        if (!run) return;
        router.post(
            `/bills/legislation_pipeline_runs/${run.id}/restart`,
            {},
            postOptions(setIsPosting, "Could not restart the pipeline run."),
        );
    }, [run]);

    const handleRun = useCallback(() => {
        router.post(
            "/bills/run_pipeline",
            {
                stages: selectedStages,
                bill_id: pickedBillId || null,
                sway_locale_id: swayLocaleId || null,
                download_missing_assets: downloadMissingAssets,
            },
            {
                preserveScroll: true,
                // @lat: [[bill-creator-pipeline-controls-panel#usePipelineRunActions notes]]
                onError: (errors: unknown) =>
                    notifyServerRefusal(errors, "pipeline", "Could not start the pipeline run."),
            },
        );
    }, [selectedStages, pickedBillId, swayLocaleId, downloadMissingAssets]);

    // @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#Stuck runs require evidence of abandonment]]
    const handleSweepStale = useCallback(async () => {
        const confirmed = await confirm({
            title: `Mark ${staleCount} stuck pipeline run${staleCount === 1 ? "" : "s"} as failed?`,
            description:
                "Only unfinished runs with no updates for 4 hours and no background job or live summary batch are marked failed. Run history is kept.",
            confirmLabel: "Mark failed",
            tone: "destructive",
        });
        if (!confirmed) return;
        router.post("/bills/sweep_stale_pipeline_runs", {}, { preserveScroll: true });
    }, [confirm, staleCount]);

    // @lat: [[bill-creator-pipeline-controls-panel#usePipelineRunActions notes]]
    const handleDeleteOrphans = useCallback(async () => {
        const confirmed = await confirm({
            title: `Permanently delete ${orphanCount} orphan pipeline run${orphanCount === 1 ? "" : "s"}?`,
            description:
                "Orphans are runs queued or running for over 4 hours with no active worker. This action cannot be undone.",
            confirmLabel: "Delete orphans",
            tone: "destructive",
        });
        if (!confirmed) return;
        router.delete("/pipeline_runs/orphans?back_to=bill_creator", { preserveScroll: true });
    }, [confirm, orphanCount]);

    return {
        isPosting,
        handleResume,
        handleRestart,
        handleRun,
        handleSweepStale,
        handleDeleteOrphans,
    };
};
