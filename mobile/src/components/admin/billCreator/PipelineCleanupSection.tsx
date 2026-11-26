// @lat: [[mobile-bill-creator#Sections#The pipeline cleanup section]]
import React, { useState } from "react";
import { Text, View } from "react-native";

import { Routes } from "../../../api/routes";
import { useAdminMutation } from "../../../hooks/admin/useAdminMutation";
import type { BillCreatorTabProps } from "../../../hooks/admin/useBillCreator";
import { useTwoTapConfirm } from "../../../hooks/useTwoTapConfirm";
import { FormField } from "../../ui/FormField";
import { Pressable } from "../../ui/Pressable";
import { isInFlight } from "./PipelineProgressSection";
import { reasonFor } from "./PipelineRunActionsSection";

const CONFIRM_PHRASE = "force fail";

const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";
const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";
const errorText = "text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark";

const countOf = (value: unknown) => (typeof value === "number" ? value : 0);

const runs = (count: number, noun: string) => `${count} ${noun} run${count === 1 ? "" : "s"}`;

interface ForceFailControlProps {
    runId: number;
    refresh: () => Promise<void>;
}

const ForceFailControl: React.FC<ForceFailControlProps> = ({ runId, refresh }) => {
    const [open, setOpen] = useState(false);
    const [phrase, setPhrase] = useState("");
    const { run, loading, errorMessage, fieldErrors } = useAdminMutation<unknown>(
        "post",
        Routes.adminPipelineRunForceFail(runId),
    );

    const close = () => {
        setPhrase("");
        setOpen(false);
    };

    const confirm = async () => {
        if ((await run({ confirm_phrase: phrase })) === undefined) return;
        close();
        await refresh();
    };

    if (!open) {
        return (
            <Pressable testID="admin-pipeline-force-fail" variant="destructive" onPress={() => setOpen(true)}>
                <Text className={labelText}>Force fail</Text>
            </Pressable>
        );
    }

    const reason = reasonFor(fieldErrors, errorMessage);
    return (
        <View testID="admin-pipeline-force-fail-panel" className="gap-2">
            <Text className={mutedText}>This will immediately mark the run as failed.</Text>
            <FormField
                testID="admin-pipeline-force-fail-phrase"
                label={`Type "${CONFIRM_PHRASE}" to confirm`}
                value={phrase}
                onChangeText={setPhrase}
                disabled={loading}
            />
            <Pressable
                testID="admin-pipeline-force-fail-confirm"
                variant="destructive"
                disabled={phrase !== CONFIRM_PHRASE || loading}
                onPress={() => void confirm()}
            >
                <Text className={labelText}>Force fail</Text>
            </Pressable>
            <Pressable testID="admin-pipeline-force-fail-cancel" variant="outline" disabled={loading} onPress={close}>
                <Text className={labelText}>Cancel</Text>
            </Pressable>
            {reason ? (
                <Text testID="admin-pipeline-force-fail-error" className={errorText}>
                    {reason}
                </Text>
            ) : null}
        </View>
    );
};

interface BulkCleanupProps {
    testID: string;
    visible: boolean;
    label: string;
    armedLabel: string;
    hint: string;
    loading: boolean;
    errorMessage: string | null;
    result: string | null;
    onConfirm: () => Promise<void>;
}

const BulkCleanup: React.FC<BulkCleanupProps> = ({
    testID,
    visible,
    label,
    armedLabel,
    hint,
    loading,
    errorMessage,
    result,
    onConfirm,
}) => {
    const { confirming, arm, disarm } = useTwoTapConfirm();

    const press = async () => {
        if (!confirming) {
            arm();
            return;
        }
        disarm();
        await onConfirm();
    };

    return (
        <View className="gap-1">
            {visible ? (
                <>
                    <Pressable testID={testID} variant="destructive" disabled={loading} onPress={() => void press()}>
                        <Text className={labelText}>{confirming ? armedLabel : label}</Text>
                    </Pressable>
                    <Text className={mutedText}>{hint}</Text>
                </>
            ) : null}
            {errorMessage ? (
                <Text testID={`${testID}-error`} className={errorText}>
                    {errorMessage}
                </Text>
            ) : null}
            {result ? (
                <Text testID={`${testID}-result`} className={labelText}>
                    {result}
                </Text>
            ) : null}
        </View>
    );
};

export default function PipelineCleanupSection({ data, refresh }: BillCreatorTabProps) {
    const run = (data.legislation_pipeline_run ?? null) as { id: number; status: string | null } | null;
    const staleCount = countOf(data.stale_pipeline_run_count);
    const orphanCount = countOf(data.orphan_pipeline_run_count);
    const [sweepResult, setSweepResult] = useState<string | null>(null);
    const [orphanResult, setOrphanResult] = useState<string | null>(null);
    const sweep = useAdminMutation<{ count: number }>("post", Routes.adminSweepStalePipelineRuns());
    const orphans = useAdminMutation<{ count: number }>("delete", Routes.adminDeleteOrphanPipelineRuns());

    const sweepStale = async () => {
        setSweepResult(null);
        const response = await sweep.run({});
        if (response === undefined) return;
        setSweepResult(`Cleared ${runs(response?.count ?? 0, "stuck pipeline")}.`);
        await refresh();
    };

    const deleteOrphans = async () => {
        setOrphanResult(null);
        const response = await orphans.run();
        if (response === undefined) return;
        const count = response?.count ?? 0;
        setOrphanResult(count === 0 ? "No orphan runs to remove." : `Removed ${runs(count, "orphan")}.`);
        await refresh();
    };

    const failableRun = run && isInFlight(run.status) ? run : null;
    if (!failableRun && staleCount === 0 && orphanCount === 0 && !sweepResult && !orphanResult) return null;

    return (
        <View testID="admin-pipeline-cleanup" className="px-4 mt-6 gap-3">
            {failableRun ? <ForceFailControl key={failableRun.id} runId={failableRun.id} refresh={refresh} /> : null}
            <BulkCleanup
                testID="admin-pipeline-sweep-stale"
                visible={staleCount > 0}
                label={`Remove ${runs(staleCount, "stuck")}`}
                armedLabel={`Tap again to mark ${runs(staleCount, "stuck")} as failed`}
                hint="Marks unfinished runs as failed only after 4 hours without updates and with no background job or live summary batch. Run history is kept."
                loading={sweep.loading}
                errorMessage={sweep.errorMessage}
                result={sweepResult}
                onConfirm={sweepStale}
            />
            <BulkCleanup
                testID="admin-pipeline-delete-orphans"
                visible={orphanCount > 0}
                label={`Delete ${runs(orphanCount, "orphan")}`}
                armedLabel={`Tap again to delete ${runs(orphanCount, "orphan")}`}
                hint="Permanently deletes runs queued or running for over 4 hours with no active worker. Cannot be undone."
                loading={orphans.loading}
                errorMessage={orphans.errorMessage}
                result={orphanResult}
                onConfirm={deleteOrphans}
            />
        </View>
    );
}
