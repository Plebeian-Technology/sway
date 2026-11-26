// @lat: [[mobile-bill-creator#Sections#The bill fields section#Declaring news evidence]]
import React from "react";
import { Text, View } from "react-native";

import { Pressable } from "../../ui/Pressable";

export type NewsUsage = "none" | "cited";

export interface EvidenceArticle {
    id: number;
    approved: boolean;
    has_text: boolean;
    url: string | null;
    title: string | null;
    source_name: string | null;
}

const OFFICIAL_HOSTS = ["baltimore.legistar.com", "mgaleg.maryland.gov", "congress.gov", "localhost", "127.0.0.1"];

const CHOICES: { value: NewsUsage; label: string }[] = [
    { value: "none", label: "No news reporting cited (official materials only)" },
    { value: "cited", label: "Cite approved news reporting" },
];

const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";
const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";
const bodyText = "text-xs font-open-sans-light text-foreground-light dark:text-foreground-dark";

const hasExternalNewsUrls = (prose: string) =>
    (prose.match(/https?:\/\/[^\s)]+/g) ?? []).some((urlText) => {
        try {
            const { hostname } = new URL(urlText);
            return !OFFICIAL_HOSTS.some((host) => hostname === host || hostname.endsWith(`.${host}`));
        } catch {
            return true;
        }
    });

interface NewsEvidenceControlsProps {
    summary: string;
    newsUsage: NewsUsage;
    onChangeNewsUsage: (usage: NewsUsage) => void;
    articles: EvidenceArticle[];
    disabled?: boolean;
}

export default function NewsEvidenceControls({
    summary,
    newsUsage,
    onChangeNewsUsage,
    articles,
    disabled = false,
}: NewsEvidenceControlsProps) {
    const citableArticles = articles.filter((article) => article.approved && article.has_text);

    return (
        <View
            testID="admin-news-evidence"
            className="mb-4 gap-3 rounded-lg border border-border-light dark:border-border-dark p-3"
        >
            <View className="gap-1">
                <Text className={labelText}>News Evidence Usage</Text>
                <Text className={mutedText}>
                    Declare whether this summary cites external reporting or relies exclusively on official materials.
                </Text>
            </View>
            {CHOICES.map((choice) => (
                <Pressable
                    key={choice.value}
                    testID={`admin-news-evidence-${choice.value}`}
                    variant={newsUsage === choice.value ? "default" : "outline"}
                    accessibilityRole="radio"
                    accessibilityState={{ checked: newsUsage === choice.value, disabled }}
                    disabled={disabled}
                    onPress={() => onChangeNewsUsage(choice.value)}
                >
                    <Text
                        className={
                            newsUsage === choice.value
                                ? "text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark"
                                : labelText
                        }
                    >
                        {choice.label}
                    </Text>
                </Pressable>
            ))}
            {newsUsage === "none" && hasExternalNewsUrls(summary) ? (
                <View testID="admin-news-evidence-none-warning" className="gap-1 rounded-lg border border-warning p-3">
                    <Text className={labelText}>Notice: External links detected in summary prose</Text>
                    <Text className={bodyText}>
                        {
                            'Summary prose contains external links, but news usage is set to "none". Please remove external links or switch to cited mode, as external news citations require "cited" mode.'
                        }
                    </Text>
                </View>
            ) : null}
            {newsUsage === "cited" ? (
                citableArticles.length > 0 ? (
                    <View testID="admin-news-evidence-articles" className="gap-2">
                        <Text className={mutedText}>
                            Link each claim in the summary to one of these approved articles.
                        </Text>
                        {citableArticles.map((article) => (
                            <View
                                key={article.id}
                                testID={`admin-news-evidence-article-${article.id}`}
                                className="gap-0.5"
                            >
                                <Text className={labelText}>{article.title || "Untitled article"}</Text>
                                <Text className={mutedText}>{article.source_name || "Unknown outlet"}</Text>
                                <Text className={bodyText} selectable>
                                    {article.url}
                                </Text>
                            </View>
                        ))}
                    </View>
                ) : (
                    <Text testID="admin-news-evidence-no-articles" className={mutedText}>
                        No approved article with text yet. Approve one on the Summary tab.
                    </Text>
                )
            ) : null}
        </View>
    );
}
