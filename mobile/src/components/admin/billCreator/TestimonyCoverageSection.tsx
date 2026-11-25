// @lat: [[mobile-bill-creator#Sections#The testimony coverage section]]
import React from "react";
import { Text, View } from "react-native";

import { countNoun } from "../../../../../app/frontend/sway_utils/countNoun";
import { formatDateTime } from "../../../../../app/frontend/sway_utils/datetimes";
import { Routes } from "../../../api/routes";
import { useAdminMutation } from "../../../hooks/admin/useAdminMutation";
import type { BillCreatorTabProps } from "../../../hooks/admin/useBillCreator";
import { Pressable } from "../../ui/Pressable";

interface TestimonyCoverage {
    state: "cleaned" | "never_run" | "failed" | "running" | "no_testimony" | "stale";
    coverage_gap: boolean;
    total_chars: number | null;
    reached_chars: number | null;
    left_out_chars: number | null;
    total_letters: number | null;
    left_out_letters: number | null;
    digest: string;
    acknowledged: boolean;
    acknowledged_by_email: string | null;
    acknowledged_at: string | null;
}

interface NoticeContent {
    title: string;
    body: string;
    variant: "info" | "warning";
}

const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";
const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";
const bodyText = "text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark";
const errorText = "text-xs font-open-sans-light text-destructive-light dark:text-destructive-dark";
const stampText = `self-start rounded border border-border-light dark:border-border-dark px-1.5 ${mutedText}`;
const panelClass: Record<NoticeContent["variant"], string> = {
    info: "gap-2 rounded-lg border border-border-light dark:border-border-dark p-3",
    warning: "gap-2 rounded-lg border border-warning p-3",
};

const charactersRead = (coverage: TestimonyCoverage) =>
    `${countNoun(coverage.reached_chars ?? 0, "character", "characters")} of ${(coverage.total_chars ?? 0).toLocaleString()}`;

const failedContent = (coverage: TestimonyCoverage): NoticeContent => {
    const title = "The clean-testimony stage failed";
    if (coverage.total_letters === null || coverage.left_out_letters === null) {
        return {
            title,
            body: `The model read the raw testimony instead. It read the first ${charactersRead(coverage)}.`,
            variant: "warning",
        };
    }
    return {
        title,
        body:
            `The model read the raw testimony instead. ${coverage.left_out_letters.toLocaleString()} of ` +
            `${countNoun(coverage.total_letters, "letter", "letters")} did not reach the model.`,
        variant: "warning",
    };
};

const cleanedContent = (coverage: TestimonyCoverage): NoticeContent => {
    const totalLetters = coverage.total_letters ?? 0;
    const leftOutLetters = coverage.left_out_letters ?? 0;
    const blocked = "The prompt reached its size limit. Approval is blocked until you acknowledge this.";

    if (leftOutLetters === 0 && (coverage.left_out_chars ?? 0) === 0) {
        return {
            title: "Testimony coverage",
            body: `All ${countNoun(totalLetters, "letter", "letters")} reached the model. Repeated text was removed first.`,
            variant: "info",
        };
    }
    if (leftOutLetters === 0) {
        return {
            title: "Some testimony did not reach the model",
            body: `${countNoun(totalLetters, "letter", "letters")} reached the model, but not in full. ${blocked}`,
            variant: "warning",
        };
    }
    return {
        title: "Some testimony did not reach the model",
        body: `${leftOutLetters.toLocaleString()} of ${countNoun(totalLetters, "letter", "letters")} did not reach the model. ${blocked}`,
        variant: "warning",
    };
};

const noticeContent = (coverage: TestimonyCoverage): NoticeContent => {
    switch (coverage.state) {
        case "running":
            return {
                title: "The clean-testimony stage is running",
                body: "These numbers come from the last run.",
                variant: "info",
            };
        case "never_run":
            return {
                title: "This testimony was not cleaned",
                body: `The clean-testimony stage has not run on this bill. The model read the first ${charactersRead(coverage)}.`,
                variant: "warning",
            };
        case "failed":
            return failedContent(coverage);
        case "stale":
            return {
                title: "This testimony needs to be cleaned again",
                body:
                    "Newer hearing testimony arrived after this bill was last cleaned, so the model read the raw " +
                    `testimony instead. It read the first ${charactersRead(coverage)}. Re-run the clean-testimony stage.`,
                variant: "warning",
            };
        default:
            return cleanedContent(coverage);
    }
};

const TestimonyCoverageSection: React.FC<BillCreatorTabProps> = ({ billId, data, refresh }) => {
    const acknowledgement = useAdminMutation<unknown>("post", Routes.billTestimonyCoverageAcknowledgement(billId ?? 0));
    const coverage = (data.testimony_coverage ?? null) as TestimonyCoverage | null;

    if (billId === null || coverage === null || coverage.state === "no_testimony") return null;

    const bill = (data.bill ?? {}) as { bill_llm_provisioning?: { generation_status?: string | null } | null };
    const generationStatus = bill.bill_llm_provisioning?.generation_status ?? null;
    const activeRun = (data.active_legislation_pipeline_run ?? null) as {
        status?: string | null;
        bill_id?: number | null;
    } | null;
    const cleanTestimonyRunning =
        activeRun?.status === "cleaning_testimony" && (activeRun.bill_id === null || activeRun.bill_id === billId);
    const runInFlight = generationStatus === "pending" || generationStatus === "generating" || !!cleanTestimonyRunning;

    const { title, body, variant } = noticeContent(coverage);
    const reason = acknowledgement.fieldErrors?.testimony_coverage;
    const refusal =
        acknowledgement.errorMessage === null
            ? null
            : typeof reason === "string" && reason.trim() !== ""
              ? reason
              : acknowledgement.errorMessage;

    const acknowledge = async () => {
        const response = await acknowledgement.run({ digest: coverage.digest });
        if (response !== undefined) await refresh();
    };

    return (
        <View className="px-4 mt-6">
            <View testID="admin-testimony-coverage" className={panelClass[variant]}>
                <Text testID="admin-testimony-coverage-title" className={labelText}>
                    {title}
                </Text>
                <Text testID="admin-testimony-coverage-body" className={bodyText}>
                    {body}
                </Text>
                {coverage.coverage_gap && coverage.acknowledged ? (
                    <View testID="admin-testimony-coverage-acknowledged" className="gap-1">
                        <Text className={stampText}>ACKNOWLEDGED</Text>
                        <Text testID="admin-testimony-coverage-acknowledged-by" className={mutedText}>
                            {`Acknowledged by ${coverage.acknowledged_by_email}${
                                coverage.acknowledged_at ? ` on ${formatDateTime(coverage.acknowledged_at)}` : ""
                            }.`}
                        </Text>
                    </View>
                ) : null}
                {coverage.coverage_gap && !coverage.acknowledged ? (
                    <Pressable
                        testID="admin-testimony-coverage-acknowledge"
                        onPress={() => void acknowledge()}
                        disabled={acknowledgement.loading || runInFlight}
                        accessibilityLabel="Acknowledge the missing testimony"
                    >
                        <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                            Acknowledge the missing testimony
                        </Text>
                    </Pressable>
                ) : null}
                {refusal ? (
                    <Text testID="admin-testimony-coverage-error" accessibilityRole="alert" className={errorText}>
                        {refusal}
                    </Text>
                ) : null}
            </View>
        </View>
    );
};

export default TestimonyCoverageSection;
