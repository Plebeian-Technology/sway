// @lat: [[mobile-bill-surface-components-design#PublicTestimonySection]]
import React, { useEffect, useState } from "react";
import { Pressable as RNPressable, Text, View } from "react-native";

import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { usePublicTestimonyLetters } from "../hooks/usePublicTestimony";
import { useTheme } from "../theme/ThemeProvider";
import { pressFeedback } from "../theme/effects";
import { swayTokens } from "../theme/tokens";
import type { PublicTestimonyCounts, PublicTestimonyStance } from "../types/bill";
import { BrowseTestimonySheet, type TStanceFilter } from "./BrowseTestimonySheet";
import { Card, CardContent, CardHeader, CardTitle } from "./ui/Card";
import { Pressable } from "./ui/Pressable";

export interface PublicTestimonySectionProps {
    billId: number;
    counts: PublicTestimonyCounts | null | undefined;
    isSignedIn: boolean;
    billTitle?: string;
    testID?: string;
}

const COPY = PARITY_COPY.publicTestimony.section;

export const hasPublicTestimony = (counts: PublicTestimonyCounts | null | undefined, isSignedIn: boolean): boolean =>
    isSignedIn && counts != null && counts.total > 0;

const PILLS: { stance: PublicTestimonyStance; label: string }[] = [
    { stance: "support", label: COPY.supportPill },
    { stance: "oppose", label: COPY.opposePill },
    { stance: "neutral", label: COPY.neutralPill },
];

export function PublicTestimonySection({ billId, counts, isSignedIn, billTitle, testID }: PublicTestimonySectionProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const rootTestID = testID ?? "public-testimony-section";
    const [filter, setFilter] = useState<TStanceFilter | null>(null);

    const shown = hasPublicTestimony(counts, isSignedIn);
    const open = shown && filter !== null;
    const { letters, error, refresh } = usePublicTestimonyLetters(billId, { enabled: open });

    useEffect(() => {
        if (!shown) setFilter(null);
    }, [shown]);

    if (!shown || counts == null) return null;

    const pillColors: Record<PublicTestimonyStance, { text: string; border: string; fill: string }> = {
        support: { text: t.success, border: t.success, fill: `${t.success}1f` },
        oppose: { text: t.destructive, border: t.destructive, fill: `${t.destructive}1f` },
        neutral: { text: t.foreground, border: t.borderStrong, fill: t.surface2 },
    };

    return (
        <>
            <Card testID={rootTestID}>
                <CardHeader>
                    <CardTitle>{COPY.heading}</CardTitle>
                    <Text className="text-sm font-open-sans text-muted-foreground-light dark:text-muted-foreground-dark">
                        {COPY.subtitle(counts.total)}
                    </Text>
                </CardHeader>
                <CardContent className="gap-4">
                    <View className="flex-row flex-wrap gap-2">
                        {PILLS.map(({ stance, label }) => {
                            const colors = pillColors[stance];
                            return (
                                <RNPressable
                                    key={stance}
                                    testID={`${rootTestID}-pill-${stance}`}
                                    accessibilityRole="button"
                                    accessibilityLabel={`View ${label.toLowerCase()} letters, ${counts[stance]}`}
                                    onPress={() => setFilter(stance)}
                                    className="items-center justify-center rounded-full border-2 px-4"
                                    style={({ pressed }) => [
                                        { minHeight: 44, borderColor: colors.border, backgroundColor: colors.fill },
                                        pressFeedback(pressed),
                                    ]}
                                >
                                    <Text
                                        className="text-sm font-open-sans-semibold"
                                        style={{ color: colors.text, fontVariant: ["tabular-nums"] }}
                                    >
                                        {`${counts[stance]} ${label}`}
                                    </Text>
                                </RNPressable>
                            );
                        })}
                    </View>
                    <Pressable
                        testID={`${rootTestID}-browse`}
                        variant="outline"
                        onPress={() => setFilter("all")}
                        accessibilityLabel={COPY.browseButton}
                    >
                        <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                            {COPY.browseButton}
                        </Text>
                    </Pressable>
                </CardContent>
            </Card>

            <BrowseTestimonySheet
                visible={open}
                onClose={() => setFilter(null)}
                counts={counts}
                letters={letters}
                error={error}
                onRetry={() => void refresh()}
                initialFilter={filter ?? "all"}
                billTitle={billTitle}
            />
        </>
    );
}

export default PublicTestimonySection;
