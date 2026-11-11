// @lat: [[mobile-membership-state#Single Authoritative State Boundary]]
import React, { useState } from "react";
import { Alert, FlatList, Text, View } from "react-native";

import { PendingChangeCard } from "./PendingChangeCard";
import { EmptyState } from "./ui/EmptyState";
import { usePendingChanges, type PendingChangeRecord } from "../hooks/usePendingChanges";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

export interface PendingChangesListProps {
    orgId: number;
    membershipId: number;
    isAdmin: boolean;
    testID?: string;
    changes?: PendingChangeRecord[];
    onRefresh?: () => Promise<void>;
}

export function PendingChangesList({
    orgId,
    membershipId,
    isAdmin,
    testID,
    changes: parentChanges,
    onRefresh,
}: PendingChangesListProps) {
    const hasParentChanges = parentChanges !== undefined;
    const {
        changes: hookChanges,
        loading,
        error,
        approve,
        reject,
        busy,
    } = usePendingChanges(orgId, membershipId, {
        enabled: !hasParentChanges,
    });

    const changes = parentChanges ?? hookChanges;
    const [actionBusyId, setActionBusyId] = useState<number | null>(null);

    const handleApprove = async (id: number) => {
        setActionBusyId(id);
        try {
            await approve(id);
            await onRefresh?.();
        } catch {
            // @lat: [[mobile-membership-state#Single Authoritative State Boundary]]
        } finally {
            setActionBusyId(null);
        }
    };

    const handleReject = async (id: number) => {
        setActionBusyId(id);
        try {
            try {
                await reject(id);
            } catch (err: unknown) {
                const message = err instanceof Error ? err.message : "Could not reject change.";
                Alert.alert("Reject failed", message);
                return;
            }

            try {
                await onRefresh?.();
            } catch {
                // @lat: [[mobile-membership-state#Single Authoritative State Boundary]]
            }
        } finally {
            setActionBusyId(null);
        }
    };

    if (loading && changes.length === 0) {
        return (
            <View testID={testID ?? "pending-changes-list"} className="p-4">
                <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                    Loading…
                </Text>
            </View>
        );
    }

    if (error) {
        return (
            <View testID={testID ?? "pending-changes-list"} className="p-4">
                <Text
                    accessibilityRole="alert"
                    className="text-sm font-open-sans-semibold text-vote-against-light dark:text-vote-against-dark"
                >
                    Could not load pending changes.
                </Text>
            </View>
        );
    }

    if (changes.length === 0) {
        return (
            <View testID={testID ?? "pending-changes-list"} className="flex-1">
                <EmptyState title={PARITY_COPY.pendingChanges.empty} />
            </View>
        );
    }

    return (
        <FlatList
            testID={testID ?? "pending-changes-list"}
            data={changes}
            keyExtractor={(item) => String(item.id)}
            renderItem={({ item }) => (
                <PendingChangeCard
                    change={item}
                    isAdmin={isAdmin}
                    onApprove={() => void handleApprove(item.id)}
                    onReject={() => void handleReject(item.id)}
                    busy={busy || actionBusyId === item.id}
                />
            )}
            contentContainerStyle={{ padding: 16 }}
        />
    );
}

export default PendingChangesList;
