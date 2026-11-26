// @lat: [[mobile-bill-creator#Sections#The pipeline run controls section]]
import React from "react";
import { Text, View } from "react-native";

import { Routes } from "../../../api/routes";
import { useAdminMutation } from "../../../hooks/admin/useAdminMutation";
import type { BillCreatorTabProps } from "../../../hooks/admin/useBillCreator";
import { Pressable } from "../../ui/Pressable";
import { ALL_STAGE_KEYS } from "./PipelineStagesSection";

interface FailedRun {
    id: number;
    status: string | null;
    kind: "single" | "all_bills" | null;
    current_stage?: string | null;
    pipeline_run_stages?: { status: string; position: number }[];
}

const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";
const errorText = "text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark";

const failedStageNumber = (run: FailedRun) => {
    const failed = run.pipeline_run_stages?.find((stage) => stage.status === "failed");
    if (failed) return failed.position;
    const index = ALL_STAGE_KEYS.indexOf(run.current_stage ?? "");
    return index >= 0 ? index + 1 : null;
};

export const reasonFor = (fieldErrors: Record<string, unknown> | null, errorMessage: string | null) =>
    typeof fieldErrors?.pipeline === "string" ? fieldErrors.pipeline : errorMessage;

interface FailedRunActionsProps {
    run: FailedRun;
    refresh: () => Promise<void>;
}

const FailedRunActions: React.FC<FailedRunActionsProps> = ({ run, refresh }) => {
    const resume = useAdminMutation<unknown>("post", Routes.adminPipelineRunResume(run.id));
    const restart = useAdminMutation<unknown>("post", Routes.adminPipelineRunRestart(run.id));
    const stageNumber = failedStageNumber(run);
    const posting = resume.loading || restart.loading;
    const reason =
        reasonFor(resume.fieldErrors, resume.errorMessage) ?? reasonFor(restart.fieldErrors, restart.errorMessage);

    const start = async (mutation: typeof resume) => {
        if ((await mutation.run({})) === undefined) return;
        await refresh();
    };

    return (
        <View testID="admin-pipeline-run-actions" className="px-4 mt-6 gap-2">
            <Pressable
                testID="admin-pipeline-resume"
                variant="default"
                disabled={posting}
                onPress={() => void start(resume)}
            >
                <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                    {stageNumber !== null ? `Resume from stage ${stageNumber}` : "Resume"}
                </Text>
            </Pressable>
            <Pressable
                testID="admin-pipeline-restart"
                variant="outline"
                disabled={posting}
                onPress={() => void start(restart)}
            >
                <Text className={labelText}>Restart entire run</Text>
            </Pressable>
            {reason ? (
                <Text testID="admin-pipeline-run-action-error" className={errorText}>
                    {reason}
                </Text>
            ) : null}
        </View>
    );
};

export default function PipelineRunActionsSection({ data, refresh }: BillCreatorTabProps) {
    const run = (data.legislation_pipeline_run ?? null) as FailedRun | null;
    if (!run || run.status !== "failed" || run.kind !== "single") return null;

    return <FailedRunActions key={run.id} run={run} refresh={refresh} />;
}
