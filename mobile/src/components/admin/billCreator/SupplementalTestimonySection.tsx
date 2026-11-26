// @lat: [[mobile-bill-creator#Sections#The testimony section#Saving and clearing the supplemental testimony]]
import React, { useState } from "react";
import { Text, TextInput, View } from "react-native";

import { Routes } from "../../../api/routes";
import { useAdminMutation } from "../../../hooks/admin/useAdminMutation";
import type { BillCreatorTabProps } from "../../../hooks/admin/useBillCreator";
import { Pressable } from "../../ui/Pressable";

interface DraftPosition {
    rejected?: boolean;
    bill_news_article_id?: number | null;
    text_version_id?: number | null;
    evidence_excerpt?: string | null;
}

interface TestimonyBill {
    bill_llm_provisioning?: {
        supplemental_testimony?: string | null;
        draft_org_positions?: DraftPosition[] | null;
    } | null;
}

type PendingWrite = "save" | "clear";

const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";
const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";
const bodyText = "text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark";
const errorText = "text-xs font-open-sans-light text-destructive-light dark:text-destructive-dark";
const primaryText = "text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark";
const panelClass = "gap-2 rounded-lg border border-border-light dark:border-border-dark p-3";
const inputClass =
    "rounded-md border border-border-light bg-input-light px-4 py-3 font-open-sans-light text-foreground-light dark:border-border-dark dark:bg-input-dark dark:text-foreground-dark";

const isTestimonySourced = (draft: DraftPosition) =>
    (draft.bill_news_article_id === null || draft.bill_news_article_id === undefined) &&
    (draft.text_version_id === null || draft.text_version_id === undefined) &&
    !draft.evidence_excerpt;

const blockedPositions = (count: number) => {
    const one = count === 1;
    return (
        `the ${count} draft position${one ? "" : "s"} on this bill ${one ? "was" : "were"} written from, ` +
        `so ${one ? "it" : "they"} can no longer be approved.`
    );
};

const CONFIRM_COPY: Record<PendingWrite, { title: string; body: (count: number) => string; confirm: string }> = {
    save: {
        title: "Save and block these positions?",
        body: (count) =>
            `Saving replaces the testimony ${blockedPositions(count)} ` +
            "Regenerate or reject them instead of pasting the old testimony back.",
        confirm: "Save testimony",
    },
    clear: {
        title: "Clear the testimony and block these positions?",
        body: (count) =>
            `Clearing removes the testimony ${blockedPositions(count)} ` +
            "Pasting the testimony back does not restore them — regenerate or reject them instead.",
        confirm: "Clear testimony",
    },
};

const FAILURE_COPY: Record<PendingWrite, string> = {
    save: "Could not save the supplemental testimony — it is not on this bill yet.",
    clear: "Could not clear the supplemental testimony — it is still on this bill.",
};

const SupplementalTestimonySection: React.FC<BillCreatorTabProps> = ({ billId, data, refresh }) => {
    const provisioning = ((data.bill ?? {}) as TestimonyBill).bill_llm_provisioning ?? null;
    const serverText = provisioning?.supplemental_testimony || "";

    // @lat: [[bill-creator-positions-tab#Saving testimony is what commits it to a run#The box takes a newer server value only when nothing is unsaved in it]]
    const [lastServerText, setLastServerText] = useState(serverText);
    const [text, setText] = useState(serverText);
    if (serverText !== lastServerText) {
        setLastServerText(serverText);
        if (text === lastServerText) setText(serverText);
    }

    const [confirming, setConfirming] = useState<PendingWrite | null>(null);
    const [lastWrite, setLastWrite] = useState<PendingWrite>("save");
    const mutation = useAdminMutation<unknown>("patch", Routes.billSupplementalTestimony(billId ?? 0));

    if (billId === null) return null;

    const testimonyPositionsCount = (provisioning?.draft_org_positions ?? []).filter(
        (draft) => !draft.rejected && isTestimonySourced(draft),
    ).length;
    // @lat: [[bill-creator-summary-tab#Supplemental testimony is replaced, never appended]]
    const replacesStoredTestimony = serverText.trim().length > 0 && !text.includes(serverText);

    const send = async (write: PendingWrite) => {
        setConfirming(null);
        setLastWrite(write);
        const body = write === "save" ? { supplemental_testimony: text } : { clear_supplemental_testimony: true };
        const response = await mutation.run(body);
        if (response !== undefined) await refresh();
    };

    const request = (write: PendingWrite) => {
        const asks = testimonyPositionsCount > 0 && (write === "clear" || replacesStoredTestimony);
        if (asks) setConfirming(write);
        else void send(write);
    };

    return (
        <View testID="admin-supplemental-testimony" className="px-4 mt-6 gap-3">
            <Text
                accessibilityRole="header"
                className="text-lg font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
            >
                Testimony and positions
            </Text>
            <Text className={mutedText}>
                Testimony never reaches the summary model. It is what the draft positions below are written from, and a
                run reads only what Save testimony has written to this bill.
            </Text>
            <Text className={mutedText}>
                For news opinion commentary, assign stances in the News articles review section on the Summary tab.
            </Text>
            <Text className={labelText}>Supplemental testimony (optional)</Text>
            <TextInput
                testID="admin-supplemental-testimony-input"
                value={text}
                onChangeText={setText}
                multiline
                numberOfLines={4}
                accessibilityLabel="Supplemental testimony"
                placeholder="Paste additional testimony or supplemental context here (optional)"
                className={inputClass}
                style={{ minHeight: 110, textAlignVertical: "top" }}
            />
            <View className="flex-row flex-wrap gap-2">
                {text !== serverText ? (
                    <Pressable
                        testID="admin-supplemental-testimony-save"
                        variant="default"
                        disabled={mutation.loading}
                        onPress={() => request("save")}
                    >
                        <Text className={primaryText}>Save testimony</Text>
                    </Pressable>
                ) : null}
                {serverText ? (
                    <Pressable
                        testID="admin-supplemental-testimony-clear"
                        variant="ghost"
                        disabled={mutation.loading}
                        onPress={() => request("clear")}
                    >
                        <Text className={labelText}>Clear saved testimony</Text>
                    </Pressable>
                ) : null}
            </View>
            {confirming ? (
                <View testID="admin-supplemental-testimony-confirm-panel" className={panelClass}>
                    <Text className={labelText}>{CONFIRM_COPY[confirming].title}</Text>
                    <Text testID="admin-supplemental-testimony-confirm-text" className={bodyText}>
                        {CONFIRM_COPY[confirming].body(testimonyPositionsCount)}
                    </Text>
                    <View className="flex-row flex-wrap gap-2">
                        <Pressable
                            testID="admin-supplemental-testimony-confirm"
                            variant="destructive"
                            disabled={mutation.loading}
                            onPress={() => void send(confirming)}
                        >
                            <Text className={primaryText}>{CONFIRM_COPY[confirming].confirm}</Text>
                        </Pressable>
                        <Pressable
                            testID="admin-supplemental-testimony-cancel"
                            variant="ghost"
                            onPress={() => setConfirming(null)}
                        >
                            <Text className={labelText}>Cancel</Text>
                        </Pressable>
                    </View>
                </View>
            ) : null}
            {mutation.errorMessage ? (
                <Text testID="admin-supplemental-testimony-error" accessibilityRole="alert" className={errorText}>
                    {`${FAILURE_COPY[lastWrite]} ${mutation.errorMessage}`}
                </Text>
            ) : null}
        </View>
    );
};

export default SupplementalTestimonySection;
