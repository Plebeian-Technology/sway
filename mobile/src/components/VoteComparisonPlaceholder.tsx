// @lat: [[voter-privacy-threshold#The mobile bill screen hides what the web hides]]
import React, { useState } from "react";
import { Share, Text, View } from "react-native";

import { AuthPromptSheet } from "./AuthPromptSheet";
import { Pressable } from "./ui/Pressable";
import { useBootstrap } from "../hooks/useBootstrap";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

export interface VoteComparisonPlaceholderProps {
    votersNeeded?: number | null;
    testID?: string;
}

const MESSAGE_CLASS = "text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";
const BUTTON_TEXT_CLASS = "text-sm font-open-sans-semibold text-accent-light dark:text-accent-dark";

export function VoteComparisonPlaceholder({ votersNeeded, testID }: VoteComparisonPlaceholderProps) {
    const { bootstrap } = useBootstrap();
    const [authPromptVisible, setAuthPromptVisible] = useState(false);
    const currentUser = bootstrap?.current_user ?? null;
    const inviteUrl = currentUser?.invite_url;

    if (votersNeeded === undefined || votersNeeded === null) {
        return (
            <Text testID={testID ?? "vote-comparison-placeholder"} className={MESSAGE_CLASS}>
                {PARITY_COPY.bill.voteComparisonPlaceholder.notEnoughVotes}
            </Text>
        );
    }

    return (
        <View testID={testID ?? "vote-comparison-placeholder"} className="gap-2">
            <Text className={MESSAGE_CLASS}>
                {PARITY_COPY.bill.voteComparisonPlaceholder.votersNeeded(votersNeeded)}
            </Text>
            <Text className={MESSAGE_CLASS}>{PARITY_COPY.bill.voteComparisonPlaceholder.invitePrompt}</Text>
            {inviteUrl ? (
                <Pressable
                    testID="vote-comparison-invite"
                    variant="ghost"
                    accessibilityLabel={PARITY_COPY.bill.voteComparisonPlaceholder.shareInviteLink}
                    onPress={() => {
                        Share.share({ message: inviteUrl, url: inviteUrl }).catch(() => {});
                    }}
                >
                    <Text className={BUTTON_TEXT_CLASS}>
                        {PARITY_COPY.bill.voteComparisonPlaceholder.shareInviteLink}
                    </Text>
                </Pressable>
            ) : null}
            {currentUser ? null : (
                <>
                    <Pressable
                        testID="vote-comparison-sign-up"
                        variant="ghost"
                        accessibilityLabel={PARITY_COPY.bill.voteComparisonPlaceholder.signUp}
                        onPress={() => setAuthPromptVisible(true)}
                    >
                        <Text className={BUTTON_TEXT_CLASS}>{PARITY_COPY.bill.voteComparisonPlaceholder.signUp}</Text>
                    </Pressable>
                    <AuthPromptSheet
                        visible={authPromptVisible}
                        heading={PARITY_COPY.bill.voteComparisonPlaceholder.signUp}
                        body={PARITY_COPY.bill.voteComparisonPlaceholder.invitePrompt}
                        onSignIn={() => setAuthPromptVisible(false)}
                        onDismiss={() => setAuthPromptVisible(false)}
                        testID="vote-comparison-auth-prompt"
                    />
                </>
            )}
        </View>
    );
}

export default VoteComparisonPlaceholder;
