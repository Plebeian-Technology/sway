// @lat: [[mobile-bill-creator#Sections#The sending services section]]
import React, { useState } from "react";
import { Alert, Text, View } from "react-native";

import { Routes } from "../../../api/routes";
import { useAdminMutation } from "../../../hooks/admin/useAdminMutation";
import type { BillCreatorTabProps } from "../../../hooks/admin/useBillCreator";
import { FormField } from "../../ui/FormField";
import { Pressable } from "../../ui/Pressable";
import CollapsibleSection from "./CollapsibleSection";

export interface SendingServiceDomainRow {
    id: number;
    domain: string;
    label: string;
    sender_count: number;
    machine_sent_letter_count: number;
    letter_count: number;
    bill_count: number;
}

const CONFIRMED_LABEL = "confirmed";
const NO_LABEL = "none";
const PAGE_SIZE = 5;

const STAMPS: Record<string, string> = { confirmed: "CONFIRMED", proposed: "PROPOSED" };

const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";
const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";
const errorText = "text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark";

const letters = (count: number) => `${count.toLocaleString()} ${count === 1 ? "letter" : "letters"}`;

const machineSentPercent = (row: SendingServiceDomainRow) =>
    row.letter_count === 0 ? 0 : Math.round((row.machine_sent_letter_count / row.letter_count) * 100);

interface DomainRowProps {
    row: SendingServiceDomainRow;
    billId: number | null;
    refresh: () => Promise<void>;
}

const DomainRow: React.FC<DomainRowProps> = ({ row, billId, refresh }) => {
    const { run, loading, errorMessage, fieldErrors } = useAdminMutation<unknown>(
        "patch",
        Routes.adminSendingServiceDomain(row.id),
    );
    const reason = typeof fieldErrors?.sending_service === "string" ? fieldErrors.sending_service : errorMessage;
    const testID = `admin-sending-service-${row.id}`;

    const applyLabel = async (label: string) => {
        if ((await run({ label, bill_id: billId })) === undefined) return;
        await refresh();
    };

    const askToConfirm = () =>
        Alert.alert(
            `Confirm ${row.domain} as a sending service?`,
            "Every future letter from this domain will be marked machine-sent. This does not say what those letters argue.",
            [
                { text: "Cancel", style: "cancel" },
                { text: "Confirm", onPress: () => void applyLabel(CONFIRMED_LABEL) },
            ],
        );

    const askToRemove = () =>
        Alert.alert(
            `Remove the sending-service label from ${row.domain}?`,
            "Future letters from this domain will be read as one person's letter.",
            [
                { text: "Cancel", style: "cancel" },
                { text: "Remove the label", style: "destructive", onPress: () => void applyLabel(NO_LABEL) },
            ],
        );

    return (
        <View
            testID={testID}
            className="rounded-lg border border-border-soft-light dark:border-border-soft-dark p-3 gap-1"
        >
            <Text className={labelText}>{row.domain}</Text>
            <Text className={mutedText}>
                {`${row.sender_count.toLocaleString()} senders · ${row.bill_count.toLocaleString()} bills`}
            </Text>
            <Text className={labelText}>{`${machineSentPercent(row)}%`}</Text>
            <Text
                className={mutedText}
            >{`${row.machine_sent_letter_count.toLocaleString()} of ${letters(row.letter_count)}`}</Text>
            <Text testID={`${testID}-stamp`} className={mutedText}>
                {STAMPS[row.label] ?? "UNLABELED"}
            </Text>
            {row.label === CONFIRMED_LABEL ? (
                <Pressable testID={`${testID}-remove`} variant="outline" disabled={loading} onPress={askToRemove}>
                    <Text className={labelText}>Remove this label</Text>
                </Pressable>
            ) : (
                <>
                    <Pressable testID={`${testID}-confirm`} variant="default" disabled={loading} onPress={askToConfirm}>
                        <Text className={labelText}>Confirm as a sending service</Text>
                    </Pressable>
                    <Pressable testID={`${testID}-not`} variant="outline" disabled={loading} onPress={askToRemove}>
                        <Text className={labelText}>Not a sending service</Text>
                    </Pressable>
                </>
            )}
            {reason ? (
                <Text testID={`${testID}-error`} className={errorText}>
                    {reason}
                </Text>
            ) : null}
        </View>
    );
};

export default function SendingServicesSection({ billId, data, refresh }: BillCreatorTabProps) {
    const domains = (data.sending_service_domains ?? []) as SendingServiceDomainRow[];
    const total = typeof data.sending_service_domains_total === "number" ? data.sending_service_domains_total : null;
    const [query, setQuery] = useState("");
    const [requestedPage, setRequestedPage] = useState(1);

    const needle = query.trim().toLowerCase();
    const filtered = needle ? domains.filter((row) => row.domain.toLowerCase().includes(needle)) : domains;
    const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
    const page = Math.min(requestedPage, pageCount);
    const pageRows = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);
    const notLoaded = total !== null && total > domains.length ? total - domains.length : 0;

    return (
        <CollapsibleSection testID="admin-sending-services" title="Sending services">
            <Text className={mutedText}>
                A sending service says only that a letter was machine-sent. It never says which campaign a letter
                belongs to, or what it argues.
            </Text>
            {notLoaded > 0 ? (
                <Text className={mutedText}>
                    {`Showing the ${domains.length.toLocaleString()} domains with the most machine-sent letters, of ${total?.toLocaleString()}.`}
                </Text>
            ) : null}
            {domains.length === 0 ? (
                <Text className={mutedText}>No sending-service domains yet.</Text>
            ) : (
                <>
                    <FormField
                        testID="admin-sending-services-search"
                        label="Search by domain"
                        value={query}
                        onChangeText={setQuery}
                    />
                    {filtered.length === 0 ? (
                        <Text className={mutedText}>
                            {notLoaded > 0
                                ? `No domains match this search among the ${domains.length.toLocaleString()} shown — ${notLoaded.toLocaleString()} more are not loaded.`
                                : "No domains match this search."}
                        </Text>
                    ) : (
                        <>
                            {pageRows.map((row) => (
                                <DomainRow key={row.id} row={row} billId={billId} refresh={refresh} />
                            ))}
                            <View className="flex-row items-center justify-between">
                                <Pressable
                                    testID="admin-sending-services-previous"
                                    variant="outline"
                                    disabled={page <= 1}
                                    onPress={() => setRequestedPage(page - 1)}
                                >
                                    <Text className={labelText}>Previous</Text>
                                </Pressable>
                                <Text className={mutedText}>{`Page ${page} of ${pageCount}`}</Text>
                                <Pressable
                                    testID="admin-sending-services-next"
                                    variant="outline"
                                    disabled={page >= pageCount}
                                    onPress={() => setRequestedPage(page + 1)}
                                >
                                    <Text className={labelText}>Next</Text>
                                </Pressable>
                            </View>
                        </>
                    )}
                </>
            )}
        </CollapsibleSection>
    );
}
