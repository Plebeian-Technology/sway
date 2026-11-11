// @lat: [[mobile-bill-surface-components-design#BillSummarySection]]
// @lat: [[news-mobile-citations#Mobile summary citations#Atomic link boundary preservation]]
import React, { useMemo, useState } from "react";
import { LayoutAnimation, Platform, Pressable as RNPressable, Text, UIManager, View } from "react-native";
import { ExternalLink } from "lucide-react-native";
import { Card, CardContent, CardHeader, CardTitle } from "./ui/Card";
import { Pressable } from "./ui/Pressable";
import { canOpenSourceLink } from "./HearingTestimonySection";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { Markdown, markdownExceedsLimit } from "./Markdown";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import { openSourceLink } from "../utils/officialSourceLink";

// @lat: [[mobile-bill-surface-components-design#BillSummarySection]]
if (Platform.OS === "android") {
    UIManager.setLayoutAnimationEnabledExperimental?.(true);
}

const PREVIEW_CHARS = 200;
const SUMMARY_PLACEHOLDER = "Summary pending";

export interface BillSummarySectionProps {
    summary?: string | null;
    // @lat: [[mobile-bill-surface-components-design#BillSummarySection]]
    summaryAiUnreviewed?: boolean;
    // @lat: [[mobile-bill-surface-components-design#BillSummarySection]]
    billLink?: string | null;
    showSourceNotice?: boolean;
    genericPortalUrls?: string[];
    swayLocaleSlug?: string;
    allowedSourceHosts?: readonly string[];
    testID?: string;
}

export function BillSummarySection({
    summary,
    summaryAiUnreviewed,
    billLink,
    showSourceNotice = false,
    genericPortalUrls,
    swayLocaleSlug,
    allowedSourceHosts,
    testID,
}: BillSummarySectionProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const [expanded, setExpanded] = useState(false);

    // @lat: [[mobile-bill-surface-components-design#BillSummarySection]]
    const clean = (summary ?? "").replace(/NEWLINE|ENDING/g, " ").trim();
    const pending = clean === "" || clean === SUMMARY_PLACEHOLDER;
    const hasMore = useMemo(() => !pending && markdownExceedsLimit(clean, PREVIEW_CHARS), [clean, pending]);

    const showAiNotice = Boolean(summaryAiUnreviewed) && !pending;
    const showSource = showSourceNotice;
    const sourceOpenable = canOpenSourceLink(billLink, { genericPortalUrls, swayLocaleSlug, allowedSourceHosts });

    const toggle = () => {
        LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
        setExpanded((v) => !v);
    };

    return (
        <Card testID={testID ?? "bill-summary-section"}>
            <CardHeader>
                <CardTitle>{PARITY_COPY.bill.content.swaysSummary}</CardTitle>
            </CardHeader>
            <CardContent>
                {pending ? (
                    <Text
                        testID="bill-summary-pending"
                        className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                    >
                        {PARITY_COPY.bill.summaryPending}
                    </Text>
                ) : (
                    <Markdown
                        content={clean}
                        maxChars={PREVIEW_CHARS}
                        expanded={expanded}
                        className="text-base font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                    />
                )}
                {hasMore ? (
                    <Pressable
                        variant="ghost"
                        onPress={toggle}
                        accessibilityLabel={expanded ? PARITY_COPY.bill.showLess : PARITY_COPY.bill.showMore}
                        accessibilityRole="button"
                        accessibilityState={{ expanded }}
                    >
                        <Text className="text-sm font-open-sans-semibold text-accent-light dark:text-accent-dark">
                            {expanded ? PARITY_COPY.bill.showLess : PARITY_COPY.bill.showMore}
                        </Text>
                    </Pressable>
                ) : null}
                {showAiNotice || showSource ? (
                    <View
                        testID="bill-summary-notice"
                        className="mt-3 pt-3 gap-1 border-t border-border-light dark:border-border-dark"
                    >
                        {showAiNotice ? (
                            <Text
                                testID="ai-unreviewed-notice"
                                className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark"
                            >
                                {PARITY_COPY.bill.aiUnreviewedNotice}
                            </Text>
                        ) : null}
                        {showSource && sourceOpenable ? (
                            <RNPressable
                                testID="bill-source-text-link"
                                onPress={() => openSourceLink(billLink as string)}
                                accessibilityRole="link"
                                accessibilityLabel={PARITY_COPY.bill.viewOriginalText}
                                accessibilityHint="Opens an external website in your browser"
                                className="flex-row items-center gap-2 self-start"
                                style={{ minHeight: 44 }}
                            >
                                <Text className="shrink text-sm font-open-sans-semibold text-accent-light dark:text-accent-dark underline">
                                    {PARITY_COPY.bill.viewOriginalText}
                                </Text>
                                <ExternalLink size={14} color={t.accent} />
                            </RNPressable>
                        ) : null}
                        {showSource && !sourceOpenable ? (
                            <Text
                                testID="summary-no-source-link"
                                className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark"
                            >
                                {PARITY_COPY.bill.officialSourceUnavailable}
                            </Text>
                        ) : null}
                    </View>
                ) : null}
            </CardContent>
        </Card>
    );
}
