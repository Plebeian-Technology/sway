// @lat: [[user-vote-submission#Mobile vote controls]]
import React, { useEffect, useState } from "react";
import { Modal, View, Text } from "react-native";

import { VoteButton } from "./VoteButton";
import { AuthPromptSheet } from "./AuthPromptSheet";
import { Pressable } from "./ui/Pressable";
import { useSession } from "../hooks/useSession";
import { useCastUserVote } from "../hooks/useCastUserVote";
import { ApiRequestError } from "../api/errors";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import { shadowBold } from "../theme/effects";
import * as voteCache from "../cache/voteCache";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { billHeadline } from "../utils/billTitle";

interface VotePanelBill {
    id: number;
    title: string;
    headline?: string;
    external_id?: string;
    active?: boolean;
    scheduled_release_date_utc?: string | null;
}

interface VotePanelUserVote {
    support?: "for" | "against" | "FOR" | "AGAINST" | null;
}

export interface VotePanelProps {
    bill: VotePanelBill;
    user_vote?: VotePanelUserVote | null;
    // @lat: [[user-vote-submission#Mobile vote controls]]
    onVoted?: () => void;
    onSignInRequested?: () => void;
    // @lat: [[user-vote-submission#Mobile vote controls]]
    className?: string;
    testID?: string;
}

function normaliseUserVote(s: VotePanelUserVote["support"]): "for" | "against" | null {
    if (!s) return null;
    const lower = s.toString().toLowerCase();
    if (lower === "for" || lower === "against") return lower;
    return null;
}

export function VotePanel({
    bill,
    user_vote,
    onVoted,
    onSignInRequested,
    className = "mt-6 mb-2",
    testID,
}: VotePanelProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const { isAuthenticated } = useSession();
    const { submit, isOnline } = useCastUserVote();
    const headline = bill.headline ?? billHeadline(bill.title);
    const [userVote, setUserVote] = useState<"for" | "against" | null>(normaliseUserVote(user_vote?.support));
    const [error, setError] = useState<string | null>(null);
    const [authPromptVisible, setAuthPromptVisible] = useState(false);
    const [pendingUserVote, setPendingUserVote] = useState<"for" | "against" | null>(null);
    const [submitting, setSubmitting] = useState(false);

    // @lat: [[user-vote-submission#Mobile vote restoration]]
    useEffect(() => {
        const fromProps = normaliseUserVote(user_vote?.support);
        if (fromProps) {
            setUserVote(fromProps);
            return;
        }
        setUserVote(null);
        let cancelled = false;
        void voteCache.get(bill.id).then((row) => {
            if (cancelled || !row) return;
            const cached = normaliseUserVote((row.vote as { support?: VotePanelUserVote["support"] }).support);
            if (cached) setUserVote(cached);
        });
        return () => {
            cancelled = true;
        };
    }, [bill.id, user_vote?.support]);

    const requestUserVote = (support: "for" | "against") => {
        setError(null);
        if (!isAuthenticated) {
            setAuthPromptVisible(true);
            return;
        }
        setPendingUserVote(support);
    };

    const confirmUserVote = async () => {
        if (!pendingUserVote) return;
        setSubmitting(true);
        try {
            await submit(bill.id, pendingUserVote);
            setUserVote(pendingUserVote);
            onVoted?.();
            setPendingUserVote(null);
        } catch (e: unknown) {
            const msg = e instanceof Error ? e.message : String(e);
            setError(
                msg === "offline_write_blocked"
                    ? PARITY_COPY.vote.offlineMessage
                    : e instanceof ApiRequestError && e.code === "bill_inactive"
                      ? e.message
                      : "Vote failed. Please try again.",
            );
            setPendingUserVote(null);
        } finally {
            setSubmitting(false);
        }
    };

    const isBillClosed = bill.active === false;
    const isVoteDisabled = !isOnline || userVote !== null || isBillClosed;
    // @lat: [[user-vote-submission#Disabled mobile vote hints]]
    const caption = error
        ? null
        : userVote !== null
          ? PARITY_COPY.votePanel.recordedVote(userVote === "for" ? "FOR" : "AGAINST")
          : isBillClosed
            ? PARITY_COPY.votePanel.archivedBill
            : !isOnline
              ? PARITY_COPY.vote.offlineMessage
              : null;

    return (
        <View testID={testID ?? "vote-panel"} className={className}>
            <Text
                className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark mb-3"
                accessibilityRole="header"
            >
                {PARITY_COPY.votePanel.title}
            </Text>
            <View className="flex-row gap-3">
                <VoteButton
                    userVote={userVote}
                    onPress={() => requestUserVote("for")}
                    disabled={isVoteDisabled}
                    disabledHint={!isOnline ? "You're offline — votes require a connection." : undefined}
                    billTitle={headline}
                    label={PARITY_COPY.votePanel.forLabel}
                    testID="vote-panel-for"
                />
                <VoteButton
                    userVote={userVote}
                    onPress={() => requestUserVote("against")}
                    disabled={isVoteDisabled}
                    disabledHint={!isOnline ? "You're offline — votes require a connection." : undefined}
                    billTitle={headline}
                    label={PARITY_COPY.votePanel.againstLabel}
                    testID="vote-panel-against"
                />
            </View>
            {caption ? (
                <Text
                    testID="vote-panel-caption"
                    className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark mt-3"
                    accessibilityLiveRegion="polite"
                >
                    {caption}
                </Text>
            ) : null}
            {error ? (
                <Text
                    testID="vote-panel-error"
                    className="text-sm font-open-sans-semibold text-vote-against-light dark:text-vote-against-dark mt-3"
                    accessibilityLiveRegion="polite"
                >
                    {error}
                </Text>
            ) : null}
            <AuthPromptSheet
                visible={authPromptVisible}
                onSignIn={() => {
                    setAuthPromptVisible(false);
                    onSignInRequested?.();
                }}
                onDismiss={() => setAuthPromptVisible(false)}
                testID="vote-panel-auth-prompt"
            />

            <Modal
                visible={pendingUserVote !== null}
                transparent
                animationType="fade"
                accessibilityViewIsModal
                onRequestClose={() => !submitting && setPendingUserVote(null)}
            >
                <View style={{ flex: 1, backgroundColor: t.scrim }} className="items-center justify-center px-6">
                    <View
                        testID="vote-panel-confirm"
                        className="w-full max-w-sm bg-card-light dark:bg-card-dark border border-border-light dark:border-border-dark rounded-card px-6 py-6 gap-4"
                        style={shadowBold(colorScheme)}
                    >
                        <Text className="text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                            Confirm your vote
                        </Text>
                        <Text className="text-base font-open-sans-light leading-6 text-muted-foreground-light dark:text-muted-foreground-dark">
                            {pendingUserVote === "for"
                                ? `Cast a "For" vote on ${headline}?`
                                : `Cast an "Against" vote on ${headline}?`}
                        </Text>
                        <View className="flex-row gap-3 mt-1">
                            <Pressable
                                variant="outline"
                                onPress={() => setPendingUserVote(null)}
                                disabled={submitting}
                                accessibilityLabel="Cancel vote"
                                testID="vote-panel-confirm-cancel"
                            >
                                <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                    Cancel
                                </Text>
                            </Pressable>
                            <Pressable
                                variant="default"
                                onPress={() => void confirmUserVote()}
                                disabled={submitting}
                                accessibilityLabel="Confirm vote"
                                testID="vote-panel-confirm-submit"
                            >
                                <Text className="text-base font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                                    {submitting ? "Submitting…" : "Confirm"}
                                </Text>
                            </Pressable>
                        </View>
                    </View>
                </View>
            </Modal>
        </View>
    );
}

export default VotePanel;
