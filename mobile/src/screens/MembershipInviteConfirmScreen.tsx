// @lat: [[membership-invite-accept-flow#Mobile: MembershipInviteConfirmScreen, the confirm step for an emailed link]]
import React, { useEffect, useState } from "react";
import { ScrollView, Text } from "react-native";
import { useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";

import { apiClient } from "../api/client";
import { GENERIC_ERROR_MESSAGE } from "../api/errors";
import { Routes } from "../api/routes";
import { SkeletonCard } from "../components/SkeletonCard";
import { Card, CardContent, CardHeader, CardTitle } from "../components/ui/Card";
import { EmptyState } from "../components/ui/EmptyState";
import { Pressable } from "../components/ui/Pressable";
import type { ProfileStackParamList } from "../navigation/types";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

interface IProps {
    route: { params?: { orgId?: number; token?: string } };
}

interface InviteConfirmation {
    organization: { name: string };
    inviter_name: string | null;
}

const messageFrom = (error: unknown): string => (error instanceof Error ? error.message : GENERIC_ERROR_MESSAGE);

const MembershipInviteConfirmScreen: React.FC<IProps> = ({ route }) => {
    const navigation = useNavigation<NativeStackNavigationProp<ProfileStackParamList, "MembershipInviteConfirm">>();
    const orgId = route.params?.orgId ?? Number.NaN;
    const token = encodeURIComponent(route.params?.token ?? "");
    const isInviteLink = Number.isInteger(orgId) && orgId > 0 && token !== "";

    const [confirmation, setConfirmation] = useState<InviteConfirmation | null>(null);
    const [loadError, setLoadError] = useState<string | null>(isInviteLink ? null : "Invitation not found.");
    const [acceptError, setAcceptError] = useState<string | null>(null);
    const [accepting, setAccepting] = useState(false);

    useEffect(() => {
        if (!isInviteLink) return undefined;

        let stillShowing = true;
        apiClient
            .get<InviteConfirmation>(Routes.confirmInvite(orgId, token))
            .then((loaded) => {
                if (stillShowing) setConfirmation(loaded);
            })
            .catch((error: unknown) => {
                if (stillShowing) setLoadError(messageFrom(error));
            });
        return () => {
            stillShowing = false;
        };
    }, [isInviteLink, orgId, token]);

    const accept = async () => {
        setAccepting(true);
        setAcceptError(null);
        try {
            await apiClient.post(Routes.acceptInvite(orgId, token), undefined);
            navigation.replace("MembershipsList");
        } catch (error) {
            setAcceptError(messageFrom(error));
            setAccepting(false);
        }
    };

    const mutedText = "text-sm font-open-sans text-muted-foreground-light dark:text-muted-foreground-dark";

    return (
        <ScrollView
            testID="membership-invite-confirm-screen"
            className="flex-1 bg-dominant-light p-4 dark:bg-dominant-dark"
            contentInsetAdjustmentBehavior="automatic"
        >
            {loadError !== null ? (
                <EmptyState
                    title={loadError}
                    ctaLabel={PARITY_COPY.memberships.title}
                    onCtaPress={() => navigation.replace("MembershipsList")}
                    testID="invite-confirm-error"
                />
            ) : confirmation === null ? (
                <SkeletonCard heightClass="h-32" />
            ) : (
                <Card>
                    <CardHeader>
                        <CardTitle>Accept invitation to {confirmation.organization.name}</CardTitle>
                        {confirmation.inviter_name ? (
                            <Text className={mutedText}>Invited by {confirmation.inviter_name}</Text>
                        ) : null}
                    </CardHeader>
                    <CardContent>
                        {acceptError !== null ? (
                            <Text
                                accessibilityRole="alert"
                                className="mb-4 text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark"
                            >
                                {acceptError}
                            </Text>
                        ) : null}
                        <Pressable
                            testID="invite-confirm-accept"
                            onPress={() => void accept()}
                            disabled={accepting}
                            accessibilityLabel={PARITY_COPY.memberships.acceptLabel}
                        >
                            <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                                {PARITY_COPY.memberships.acceptLabel}
                            </Text>
                        </Pressable>
                    </CardContent>
                </Card>
            )}
        </ScrollView>
    );
};

export default MembershipInviteConfirmScreen;
