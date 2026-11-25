// @lat: [[voter-privacy-threshold#The mobile bill screen hides what the web hides]]
import React, { useState } from "react";
import { Text, View } from "react-native";
import * as Clipboard from "expo-clipboard";

import { Pressable } from "./ui/Pressable";
import { useBootstrap } from "../hooks/useBootstrap";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

export interface VoteComparisonPlaceholderProps {
    votersNeeded?: number | null;
    isSignedIn?: boolean;
    testID?: string;
}

const MESSAGE_CLASS = "text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";
const BUTTON_TEXT_CLASS = "text-sm font-open-sans-semibold text-accent-light dark:text-accent-dark";

export function VoteComparisonPlaceholder({
    votersNeeded,
    isSignedIn = false,
    testID,
}: VoteComparisonPlaceholderProps) {
    const { bootstrap } = useBootstrap();
    const [inviteLinkCopied, setInviteLinkCopied] = useState(false);
    const inviteUrl = isSignedIn ? bootstrap?.current_user?.invite_url : null;

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
                    accessibilityLabel={PARITY_COPY.bill.voteComparisonPlaceholder.copyInviteLink}
                    onPress={() => {
                        Clipboard.setStringAsync(inviteUrl)
                            .then(setInviteLinkCopied)
                            .catch(() => {});
                    }}
                >
                    <Text className={BUTTON_TEXT_CLASS}>
                        {PARITY_COPY.bill.voteComparisonPlaceholder.copyInviteLink}
                    </Text>
                </Pressable>
            ) : null}
            {inviteLinkCopied ? (
                <Text accessibilityLiveRegion="polite" className={MESSAGE_CLASS}>
                    {PARITY_COPY.bill.voteComparisonPlaceholder.inviteLinkCopied}
                </Text>
            ) : null}
        </View>
    );
}

export default VoteComparisonPlaceholder;
