// @lat: [[organization-affiliation-labels#Organization affiliation labels#A compiled position names its source]]
import React from "react";
import { Linking, Text } from "react-native";

import { Pressable } from "./ui/Pressable";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { isSafeCitationUrl } from "../utils/safeUrl";

type SourceKind = "hearing_testimony" | "news_article" | "sway_admin" | "organization" | null;

const SOURCE_LABELS: Partial<Record<NonNullable<SourceKind>, string>> = {
    hearing_testimony: PARITY_COPY.orgs.sourceHearingTestimony,
    news_article: PARITY_COPY.orgs.sourceNewsArticle,
};

export interface PositionSourceLineProps {
    sourceKind?: SourceKind;
    sourceUrl?: string | null;
    onOpenUrl?: (url: string) => void | Promise<void>;
}

export function PositionSourceLine({ sourceKind, sourceUrl, onOpenUrl }: PositionSourceLineProps) {
    const label = sourceKind ? SOURCE_LABELS[sourceKind] : undefined;
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
