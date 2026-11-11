// @lat: [[mobile-chrome-sheets-design#AuthPromptSheet]]
import React from "react";
import { Modal, Pressable, Text, View } from "react-native";

import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import { shadowBold } from "../theme/effects";

export interface AuthPromptSheetProps {
    visible: boolean;
    onSignIn: () => void;
    onDismiss: () => void;
    heading?: string;
    body?: string;
    testID?: string;
}

const DEFAULT_HEADING = "Sign in to vote";
const DEFAULT_BODY = "Track your legislators and vote on bills in your district.";

export function AuthPromptSheet({
    visible,
    onSignIn,
    onDismiss,
    heading = DEFAULT_HEADING,
    body = DEFAULT_BODY,
    testID = "auth-prompt-sheet",
}: AuthPromptSheetProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    return (
        <Modal
            visible={visible}
            transparent
            animationType="slide"
            presentationStyle="overFullScreen"
            onRequestClose={onDismiss}
            testID={testID}
        >
            <Pressable
                accessibilityRole="button"
                accessibilityLabel="Dismiss sign-in prompt"
                onPress={onDismiss}
                style={{
                    flex: 1,
                    backgroundColor: t.scrim,
                    justifyContent: "flex-end",
                }}
            >
                {/* @lat: [[mobile-chrome-sheets-design#Sheet backdrop: tap-through guard]] */}
                <Pressable
                    accessibilityRole="none"
                    onPress={() => {}}
                    className="bg-secondary-light dark:bg-secondary-dark rounded-t-2xl border border-border-light dark:border-border-dark"
                >
                    <View className="p-6">
                        <Text className="text-3xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark mb-3">
                            {heading}
                        </Text>
                        <Text className="text-base font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark mb-6">
                            {body}
                        </Text>

                        <Pressable
                            onPress={onSignIn}
                            accessibilityRole="button"
                            accessibilityLabel="Sign in"
                            testID="btn-auth-prompt-sign-in"
                            className="min-h-[44px] border border-border-light dark:border-border-dark bg-accent-light dark:bg-accent-dark rounded-lg items-center justify-center mb-3"
                            style={shadowBold(colorScheme)}
                        >
                            <Text className="text-white text-sm font-open-sans-semibold py-3">Sign in</Text>
                        </Pressable>

                        <Pressable
                            onPress={onDismiss}
                            accessibilityRole="link"
                            accessibilityLabel="Continue browsing"
                            testID="btn-auth-prompt-continue-browsing"
                            className="min-h-[44px] items-center justify-center"
                        >
                            <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                                Continue browsing
                            </Text>
                        </Pressable>
                    </View>
                </Pressable>
            </Pressable>
        </Modal>
    );
}

export default AuthPromptSheet;
