import React from "react";
import { Linking, Pressable, Text, View } from "react-native";
import { ExternalLink } from "lucide-react-native";

import { Card, CardContent, CardHeader, CardTitle } from "./ui/Card";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import { isSafeCitationUrl } from "../utils/safeUrl";
import { WarningStamp } from "./WarningStamp";
import type { RelatedNewsArticle } from "../types/bill";

// @lat: [[news-mobile-links#Placement outside summary and testimony]]
// @lat: [[news-mobile-links#Mobile link safety and external navigation]]

export { type RelatedNewsArticle } from "../types/bill";

export interface RelatedNewsArticlesProps {
    articles?: RelatedNewsArticle[] | null;
    testID?: string;
    onOpenUrl?: (url: string) => void | Promise<void>;
}

const TITLE_LINK_HIT_SLOP = { top: 12, bottom: 8 } as const;

function formatPublishedDate(publishedAt: string | null | undefined): string | null {
    if (!publishedAt) return null;
    try {
        const d = new Date(publishedAt);
        if (isNaN(d.getTime())) return null;
        return d.toLocaleDateString("en-US", {
            month: "long",
            day: "numeric",
            year: "numeric",
            timeZone: "UTC",
        });
    } catch {
        return null;
    }
}

export function RelatedNewsArticles({
    articles,
    testID = "related-news-articles",
    onOpenUrl,
}: RelatedNewsArticlesProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    if (!articles || articles.length === 0) {
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
        <Card testID={testID}>
            <CardHeader>
                <CardTitle>Related news</CardTitle>
            </CardHeader>
            <CardContent className="gap-3">
                {articles.map((article, index) => {
                    const safe = isSafeCitationUrl(article.url);
                    const formattedDate = formatPublishedDate(article.published_at);
                    const isLast = index === articles.length - 1;

                    return (
                        <View
                            key={article.id}
                            testID={`related-article-${article.id}`}
                            className={`gap-1.5 ${isLast ? "" : "border-b border-border-soft-light dark:border-border-soft-dark pb-3"}`}
                        >
                            {safe ? (
                                <Pressable
                                    accessibilityRole="link"
                                    accessibilityLabel={article.title}
                                    accessibilityHint="Opens article in browser"
                                    onPress={() => handlePress(article.url)}
                                    hitSlop={TITLE_LINK_HIT_SLOP}
                                    className="flex-row items-start justify-between gap-2"
                                >
                                    <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark flex-1">
                                        {article.title}
                                    </Text>
                                    <View className="pt-1">
                                        <ExternalLink size={14} color={t.mutedForeground} />
                                    </View>
                                </Pressable>
                            ) : (
                                <Text
                                    selectable
                                    accessibilityRole="text"
                                    className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                                >
                                    {article.title}
                                </Text>
                            )}

                            <View className="flex-row flex-wrap items-center gap-x-2 gap-y-1">
                                <Text className="text-xs font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                    {article.outlet_name}
                                </Text>

                                {article.author_name ? (
                                    <>
                                        <Text className="text-xs text-muted-foreground-light dark:text-muted-foreground-dark">
                                            •
                                        </Text>
                                        <Text className="text-xs font-open-sans text-muted-foreground-light dark:text-muted-foreground-dark">
                                            By {article.author_name}
                                        </Text>
                                    </>
                                ) : null}

                                {formattedDate ? (
                                    <>
                                        <Text className="text-xs text-muted-foreground-light dark:text-muted-foreground-dark">
                                            •
                                        </Text>
                                        <Text className="text-xs font-open-sans text-muted-foreground-light dark:text-muted-foreground-dark">
                                            {formattedDate}
                                        </Text>
                                    </>
                                ) : null}

                                <View className="flex-row flex-wrap items-center gap-1.5 ml-auto">
                                    {article.match_kind === "direct" ? (
                                        <View
                                            accessibilityRole="text"
                                            className="bg-accent-light/15 dark:bg-accent-dark/20 border border-accent-light/40 dark:border-accent-dark/40 px-2 py-0.5 rounded-sm"
                                        >
                                            <Text className="text-xs font-open-sans-semibold text-accent-light dark:text-accent-dark">
                                                Direct coverage
                                            </Text>
                                        </View>
                                    ) : null}

                                    {article.match_kind === "context" ? (
                                        <View
                                            accessibilityRole="text"
                                            className="bg-surface-2-light dark:bg-surface-2-dark border border-border-soft-light dark:border-border-soft-dark px-2 py-0.5 rounded-sm"
                                        >
                                            <Text className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark">
                                                Context
                                            </Text>
                                        </View>
                                    ) : null}

                                    {article.article_kind === "op_ed" || article.article_kind === "opinion" ? (
                                        <WarningStamp label="Op-ed" />
                                    ) : null}

                                    {article.article_kind === "editorial" ? <WarningStamp label="Editorial" /> : null}
                                </View>
                            </View>
                        </View>
                    );
                })}
            </CardContent>
        </Card>
    );
}

export default RelatedNewsArticles;
