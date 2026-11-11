import React from "react";
import { Linking, Pressable, Text, View } from "react-native";
import { ExternalLink } from "lucide-react-native";

import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import { isSafeCitationUrl } from "../utils/safeUrl";
import { CitedMarkdown } from "./CitedMarkdown";
import { WarningStamp } from "./WarningStamp";
import type { NewsArticleTestimony as NewsArticleTestimonyType } from "../types/bill";

// @lat: [[news-mobile-testimony#News mobile testimony]]
// @lat: [[news-mobile-testimony#Attribution fidelity and institutional fallback]]
// @lat: [[news-mobile-testimony#URL safety and markdown citation parsing]]

export interface NewsArticleTestimonyProps {
    testimonies?: NewsArticleTestimonyType[] | null;
    stance?: "support" | "oppose";
    testID?: string;
    onOpenUrl?: (url: string) => void | Promise<void>;
    className?: string;
}

const OUTLET_LINK_HIT_SLOP = { top: 4, bottom: 22, left: 8, right: 8 } as const;

export function getAttribution(testimony: NewsArticleTestimonyType): { authorByline: string; outletName: string } {
    const author = testimony.author_name?.trim();
    const outletName = testimony.outlet_name || "";
    const authorByline = author
        ? `By ${author}`
        : outletName.toLowerCase().includes("editorial board")
          ? outletName
          : `${outletName} Editorial Board`;
    return {
        authorByline,
        outletName,
    };
}

export function NewsArticleTestimony({ testimonies, stance, testID, onOpenUrl, className }: NewsArticleTestimonyProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    if (!testimonies || testimonies.length === 0) {
        return null;
    }

    const filtered = testimonies.filter((item) => {
        if (stance && item.stance !== stance) return false;
        if (item.stance !== "support" && item.stance !== "oppose") return false;
        return Boolean(item.argument && item.argument.trim().length > 0);
    });

    if (filtered.length === 0) {
        return null;
    }

    const handlePress = (url: string) => {
        if (!isSafeCitationUrl(url)) return;
        if (onOpenUrl) {
            void onOpenUrl(url);
            return;
        }
        void Linking.openURL(url).catch(() => {});
    };

    return (
        <View testID={testID} className={className ? `gap-4 ${className}` : "gap-4"}>
            {filtered.map((testimony) => {
                const { authorByline, outletName } = getAttribution(testimony);
                const safe = isSafeCitationUrl(testimony.url);

                return (
                    <View
                        key={testimony.id}
                        testID={`news-testimony-${testimony.id}`}
                        className="bg-surface-2-light dark:bg-surface-2-dark rounded-xl px-4 py-4 gap-2"
                    >
                        <View className="flex-row flex-wrap items-center justify-between gap-2">
                            <Text
                                selectable
                                className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                            >
                                {authorByline}
                            </Text>
                            <View className="flex-row items-center gap-1.5">
                                <WarningStamp label="News commentary" />
                                {!stance ? (
                                    <View
                                        accessibilityRole="text"
                                        className="bg-surface-1-light dark:bg-surface-1-dark border border-border-soft-light dark:border-border-soft-dark px-2 py-0.5 rounded-sm"
                                    >
                                        <Text className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark">
                                            {testimony.stance === "support" ? "Support" : "Oppose"}
                                        </Text>
                                    </View>
                                ) : null}
                            </View>
                        </View>

                        <CitedMarkdown
                            content={testimony.argument}
                            selectable
                            onOpenUrl={onOpenUrl}
                            className="text-base font-open-sans-light text-foreground-light dark:text-foreground-dark mt-2"
                        />

                        <View className="flex-row items-center gap-2 pt-1">
                            {safe ? (
                                <Pressable
                                    accessibilityRole="link"
                                    accessibilityLabel={outletName}
                                    accessibilityHint="Opens article in browser"
                                    onPress={() => handlePress(testimony.url)}
                                    hitSlop={OUTLET_LINK_HIT_SLOP}
                                    className="flex-row items-center gap-1"
                                >
                                    <Text className="text-xs font-open-sans-semibold text-accent-light dark:text-accent-dark underline">
                                        {outletName}
                                    </Text>
                                    <ExternalLink size={12} color={t.accent} />
                                </Pressable>
                            ) : (
                                <Text
                                    accessibilityRole="text"
                                    className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark"
                                >
                                    {outletName}
                                </Text>
                            )}
                        </View>
                    </View>
                );
            })}
        </View>
    );
}

export default NewsArticleTestimony;
