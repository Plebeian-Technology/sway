// @lat: [[user-vote-submission#Mobile vote controls]]
import React from "react";
import { Pressable, Text } from "react-native";
import * as Haptics from "expo-haptics";
import { pressFeedback } from "../theme/effects";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import { readableForeground } from "./StampedBadge";

export type UserVoteChoice = "for" | "against" | null;

const tapHaptic = (): void => {
    try {
        void Promise.resolve(Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light)).catch(() => undefined);
    } catch {}
};

export interface VoteButtonProps {
    userVote: UserVoteChoice;
    onPress: () => void;
    disabled?: boolean;
    disabledHint?: string;
    billTitle: string;
    label: "For" | "Against";
    testID?: string;
}

export function VoteButton({ userVote, onPress, disabled, disabledHint, billTitle, label, testID }: VoteButtonProps) {
    const lower = label.toLowerCase() as "for" | "against";
    const active = userVote === lower;
    // @lat: [[mobile-chrome-and-scroll-layout#Vote buttons wear the vote colour]]
    const toneBorder =
        lower === "for"
            ? "border-vote-for-light dark:border-vote-for-dark"
            : "border-vote-against-light dark:border-vote-against-dark";
    const toneFill =
        lower === "for" ? "bg-vote-for-light dark:bg-vote-for-dark" : "bg-vote-against-light dark:bg-vote-against-dark";
    const toneText =
        lower === "for"
            ? "text-vote-for-light dark:text-vote-for-dark"
            : "text-vote-against-light dark:text-vote-against-dark";
    const bgClass = active ? toneFill : "bg-card-light dark:bg-card-dark";
    const fgClass = active ? "" : toneText;
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const activeForeground = readableForeground(lower === "for" ? t.voteFor : t.voteAgainst);

    return (
        <Pressable
            onPress={() => {
                if (disabled) return;
                tapHaptic();
                onPress();
            }}
            disabled={disabled}
            accessibilityRole="button"
            accessibilityLabel={`Vote ${lower} ${billTitle}`}
            // @lat: [[user-vote-submission#Disabled mobile vote hints]]
            accessibilityHint={
                userVote !== null
                    ? "Your vote has already been recorded."
                    : disabled
                      ? disabledHint
                      : `Casts a "${lower}" vote on ${billTitle}.`
            }
            accessibilityState={{ selected: active, disabled: !!disabled }}
            testID={testID ?? `btn-vote-${lower}`}
            className={`flex-1 min-h-[56px] border-2 ${toneBorder} rounded-xl px-5 py-3 items-center justify-center ${bgClass}`}
            // @lat: [[user-vote-submission#Mobile vote controls]]
            style={({ pressed }) => [
                pressFeedback(pressed, disabled || active),
                disabled && !active ? { opacity: 0.55 } : null,
            ]}
        >
            <Text
                maxFontSizeMultiplier={1.3}
                numberOfLines={1}
                adjustsFontSizeToFit
                minimumFontScale={0.75}
                className={`text-lg font-open-sans-semibold ${fgClass}`}
                style={active ? { color: activeForeground } : undefined}
            >
                {label}
            </Text>
        </Pressable>
    );
}

export default VoteButton;
