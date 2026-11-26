// @lat: [[organization-affiliation-labels#Organization affiliation labels#A compiled position names its source]]
import React from "react";
import { Linking, Text } from "react-native";

import { Pressable } from "./ui/Pressable";
import {
    organizationPositionSourceLabel,
    type OrganizationPositionSourceKind,
} from "../../../app/frontend/sway_utils/organizationPositionLabels";
import { isSafeCitationUrl } from "../utils/safeUrl";

export interface PositionSourceLineProps {
    sourceKind?: OrganizationPositionSourceKind;
    sourceUrl?: string | null;
    onOpenUrl?: (url: string) => void | Promise<void>;
}

export function PositionSourceLine({ sourceKind, sourceUrl, onOpenUrl }: PositionSourceLineProps) {
    const label = organizationPositionSourceLabel(sourceKind);
    if (!label) return null;

    if (sourceUrl && isSafeCitationUrl(sourceUrl)) {
        const url = sourceUrl;
        return (
            <Pressable
                testID="org-position-source"
                variant="ghost"
                accessibilityRole="link"
                accessibilityLabel={label}
                onPress={() => {
                    if (onOpenUrl) {
                        void onOpenUrl(url);
                    } else {
                        void Linking.openURL(url).catch(() => {});
                    }
                }}
            >
                <Text className="text-xs font-open-sans-semibold text-accent-light dark:text-accent-dark">{label}</Text>
            </Pressable>
        );
    }

    return (
        <Text
            testID="org-position-source"
            className="text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
        >
            {label}
        </Text>
    );
}

export default PositionSourceLine;
