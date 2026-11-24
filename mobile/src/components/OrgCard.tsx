// @lat: [[mobile-org-membership-components-design#OrgCard]]
import React, { useState } from "react";
import { Text } from "react-native";

import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { Card, CardHeader } from "./ui/Card";
import { Pressable } from "./ui/Pressable";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import { AuthPromptSheet } from "./AuthPromptSheet";
import { OrgPreferenceSheet } from "./OrgPreferenceSheet";
import type { OrgFollowPrefs } from "../hooks/useOrganizationFollow";
import { useOrgFollowSheet } from "../hooks/useOrgFollowSheet";

export interface OrgCardOrganization {
    id: number;
    name: string;
    icon_url?: string | null;
    sway_locale_slug?: string | null;
    managed_on_sway?: boolean;
}

export interface OrgCardProps {
    org: OrgCardOrganization;
    onPress: () => void;
    // @lat: [[mobile-org-membership-components-design#OrgCard]]
    initialFollowId?: number | null;
    // @lat: [[mobile-org-membership-components-design#OrgCard]]
    isMember?: boolean;
    // @lat: [[mobile-org-membership-components-design#OrgCard]]
    isSignedIn?: boolean;
    // @lat: [[mobile-org-membership-components-design#OrgCard]]
    initialPrefs?: OrgFollowPrefs;
    // @lat: [[mobile-org-membership-components-design#OrgCard]]
    defaultPrefs?: OrgFollowPrefs;
    // @lat: [[mobile-org-membership-components-design#OrgCard]]
    onRequestSignIn?: () => void;
    testID?: string;
}

export function OrgCard({
    org,
    onPress,
    initialFollowId = null,
    isMember = false,
    isSignedIn = false,
    initialPrefs,
    defaultPrefs,
    onRequestSignIn,
    testID,
}: OrgCardProps) {
    const { colorScheme } = useTheme();
    const [showAuthSheet, setShowAuthSheet] = useState<boolean>(false);

    const {
        isFollowing,
        showPrefSheet,
        setShowPrefSheet,
        prefSheetOpenNonce,
        isFirstFollow,
        followError,
        currentInitialPrefs,
        handlePrefsSave,
        handleFollowPress,
        handleUnfollowPress,
        handlePreferencesPress,
    } = useOrgFollowSheet({
        orgId: org.id,
        initialFollowId,
        isMember,
        isSignedIn,
        initialPrefs,
        defaultPrefs,
        orgName: org.name,
        onRequireSignIn: () => {
            setShowAuthSheet(true);
        },
    });

    return (
        <>
            <Card
                onPress={onPress}
                testID={testID ?? `org-card-${org.id}`}
                accessibilityLabel={`Open organization ${org.name}`}
                className="mb-3"
                accentColor={swayTokens[colorScheme].primary}
            >
                <CardHeader>
                    <Text className="text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                        {org.name}
                    </Text>
                    {org.sway_locale_slug ? (
                        <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                            {org.sway_locale_slug}
                        </Text>
                    ) : null}
                    {org.managed_on_sway ? (
                        <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                            {PARITY_COPY.orgs.managedOnSway(org.name)}
                        </Text>
                    ) : null}

                    {/* @lat: [[mobile-org-membership-components-design#OrgCard]] */}
                    {isMember && isSignedIn ? (
                        <>
                            <Text
                                testID={`org-card-member-label-${org.id}`}
                                className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                            >
                                Member
                            </Text>
                            <Pressable
                                testID={`org-card-preferences-${org.id}`}
                                variant="outline"
                                onPress={handlePreferencesPress}
                                accessibilityLabel={`Open notification preferences for ${org.name}`}
                            >
                                <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                    Preferences
                                </Text>
                            </Pressable>
                        </>
                    ) : isFollowing && isSignedIn ? (
                        <Pressable
                            testID={`org-card-following-btn-${org.id}`}
                            variant="outline"
                            onPress={handleUnfollowPress}
                            accessibilityLabel={`Untrack ${org.name}`}
                        >
                            <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                {PARITY_COPY.orgs.tracking}
                            </Text>
                        </Pressable>
                    ) : (
                        <Pressable
                            testID={`org-card-follow-btn-${org.id}`}
                            variant="default"
                            onPress={handleFollowPress}
                            accessibilityLabel={`Track ${org.name}`}
                        >
                            <Text className="text-sm font-open-sans-semibold text-white">{PARITY_COPY.orgs.track}</Text>
                        </Pressable>
                    )}
                    {followError ? (
                        <Text
                            testID={`org-card-follow-error-${org.id}`}
                            accessibilityRole="alert"
                            className="text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark"
                        >
                            {followError}
                        </Text>
                    ) : null}
                </CardHeader>
            </Card>

            {/* @lat: [[mobile-org-membership-components-design#OrgCard]] */}
            <AuthPromptSheet
                visible={showAuthSheet}
                onSignIn={() => {
                    setShowAuthSheet(false);
                    onRequestSignIn?.();
                }}
                onDismiss={() => setShowAuthSheet(false)}
                heading="Sign in to track"
                body="Track civic organizations and get notified when Sway records their positions on legislation."
                testID={`auth-prompt-sheet-${org.id}`}
            />

            {/* @lat: [[mobile-org-membership-components-design#OrgCard#OrgPreferenceSheet wiring]] */}
            <OrgPreferenceSheet
                key={`org-pref-sheet-open-${prefSheetOpenNonce}`}
                visible={showPrefSheet}
                orgName={org.name}
                isFirstFollow={isFirstFollow}
                initialPrefs={currentInitialPrefs}
                onSave={handlePrefsSave}
                onClose={() => setShowPrefSheet(false)}
                testID={`org-pref-sheet-${org.id}`}
            />
        </>
    );
}

export default OrgCard;
