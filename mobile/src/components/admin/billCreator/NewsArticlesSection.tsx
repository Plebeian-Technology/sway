// @lat: [[mobile-bill-creator#Sections#The news articles section]]
import React, { useState } from "react";
import { Linking, Text, View } from "react-native";

import { Routes } from "../../../api/routes";
import { useAdminMutation } from "../../../hooks/admin/useAdminMutation";
import type { BillCreatorProps, BillCreatorTabProps } from "../../../hooks/admin/useBillCreator";
import { usePolling } from "../../../hooks/admin/usePolling";
import { isSafeCitationUrl } from "../../../utils/safeUrl";
import { Pressable } from "../../ui/Pressable";

interface NewsArticle {
    id: number;
    approved: boolean;
    match_kind: string | null;
    url: string | null;
    title: string | null;
    source_name: string | null;
    domain: string | null;
    author: string | null;
    published_at: string | null;
    has_text: boolean;
    text_origin: string | null;
    excerpt: string | null;
}

interface Discovery {
    receipt_status: string | null;
    articles: NewsArticle[];
    error?: string | null;
}

interface Answer {
    discovery: Discovery;
    data: BillCreatorProps;
}

const POLL_INTERVAL_MS = 5000;
const IN_FLIGHT_STATUSES = ["queued", "running"];

const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";
const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";
const bodyText = "text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark";
const errorText = "text-xs font-open-sans-light text-destructive-light dark:text-destructive-dark";
const stampText = `rounded border border-border-light dark:border-border-dark px-1.5 ${mutedText}`;
const panelClass = "gap-2 rounded-lg border border-border-light dark:border-border-dark p-3";

const discoveryFrom = (body: unknown): Discovery | null => {
    if (!body || typeof body !== "object" || !("receipt_status" in body)) return null;
    const { receipt_status, articles, error } = body as Partial<Discovery>;
    return {
        receipt_status: receipt_status ?? null,
        articles: Array.isArray(articles) ? articles : [],
        error: typeof error === "string" && error ? error : null,
    };
};

const formatDate = (iso: string) =>
    new Date(iso).toLocaleDateString("en-US", { year: "numeric", month: "short", day: "numeric" });

const ArticleTitle: React.FC<{ article: NewsArticle }> = ({ article }) => {
    const title = article.title || "Untitled article";
    const url = article.url;
    if (url === null || !isSafeCitationUrl(url)) return <Text className={labelText}>{title}</Text>;
    return (
        <Text
            testID={`admin-news-article-${article.id}-link`}
            accessibilityRole="link"
            className="text-sm font-open-sans-semibold text-primary-light dark:text-primary-dark"
            onPress={() => void Linking.openURL(url).catch(() => {})}
        >
            {title}
        </Text>
    );
};

const ArticleRow: React.FC<{ article: NewsArticle }> = ({ article }) => {
    const testID = `admin-news-article-${article.id}`;
    return (
        <View testID={testID} className={panelClass}>
            <View className="flex-row flex-wrap items-center gap-2">
                <Text className={labelText}>{article.source_name || "Unknown outlet"}</Text>
                {article.domain ? <Text className={mutedText}>{article.domain}</Text> : null}
                <Text className={stampText}>
                    {article.match_kind === "context" ? "Issue context" : "Direct coverage"}
                </Text>
                <Text className={stampText}>{article.approved ? "Approved" : "Unapproved candidate"}</Text>
            </View>
            <ArticleTitle article={article} />
            <View className="flex-row flex-wrap items-center gap-3">
                {article.author ? <Text className={mutedText}>{`by ${article.author}`}</Text> : null}
                {article.published_at ? <Text className={mutedText}>{formatDate(article.published_at)}</Text> : null}
            </View>
            {article.has_text ? (
                <View testID={`${testID}-text`} className="flex-row flex-wrap items-center gap-2">
                    <Text className={stampText}>Text Available</Text>
                    {article.approved ? <Text className={stampText}>Eligible for synthesis</Text> : null}
                    {article.text_origin ? <Text className={mutedText}>{`Origin: ${article.text_origin}`}</Text> : null}
                </View>
            ) : (
                <View testID={`${testID}-link-only`} className="gap-1">
                    <Text className={stampText}>Link-only</Text>
                    <Text className={mutedText}>
                        No article text available. This article will be included as an external link on web and mobile.
                        Cannot be cited in summary synthesis until text is provided.
                    </Text>
                </View>
            )}
            {article.has_text && article.excerpt ? (
                <Text testID={`${testID}-excerpt`} className={bodyText} numberOfLines={3}>
                    {article.excerpt}
                </Text>
            ) : null}
        </View>
    );
};

const ReceiptNotice: React.FC<{ status: string | null; requestError: string | null }> = ({ status, requestError }) => {
    if (status === "succeeded") {
        return (
            <Text testID="admin-news-succeeded" className={bodyText}>
                Discovery completed successfully.
            </Text>
        );
    }
    if (status === "no_matches") {
        return (
            <Text testID="admin-news-no-matches" className={mutedText}>
                No matching articles found for this bill in configured newsroom sources.
            </Text>
        );
    }
    if (status === "unsupported") {
        return (
            <Text testID="admin-news-unsupported" accessibilityRole="alert" className={bodyText}>
                News discovery is not supported for this provider or locale.
            </Text>
        );
    }
    if (status === "failed") {
        return (
            <Text testID="admin-news-failed" accessibilityRole="alert" className={errorText}>
                {`Failed to fetch articles from news sources.${requestError ? ` (${requestError})` : ""}`}
            </Text>
        );
    }
    return null;
};

const NewsArticlesSection: React.FC<BillCreatorTabProps> = ({ billId, data, refresh }) => {
    const { run, loading, errorMessage, errorBody } = useAdminMutation<Discovery>(
        "post",
        billId === null ? "" : Routes.adminBillNewsArticles(billId),
    );
    const [answer, setAnswer] = useState<Answer | null>(null);

    const refusal = discoveryFrom(errorBody);
    const requestError = loading ? null : refusal ? (refusal.error ?? null) : errorMessage;
    const answered = refusal ?? (answer !== null && answer.data === data ? answer.discovery : null);

    let receiptStatus: string | null = (data.receipt_status as string | null | undefined) ?? null;
    if (loading) receiptStatus = null;
    else if (answered !== null) receiptStatus = answered.receipt_status;
    else if (requestError !== null) receiptStatus = "failed";

    const articles = answered?.articles ?? (data.news_articles as NewsArticle[] | undefined) ?? [];

    usePolling(refresh, receiptStatus !== null && IN_FLIGHT_STATUSES.includes(receiptStatus), POLL_INTERVAL_MS);

    const fetchArticles = async () => {
        setAnswer(null);
        const result = await run({});
        if (result) setAnswer({ discovery: result, data });
    };

    return (
        <View testID="admin-news-articles" className="px-4 mt-6 gap-2">
            <Text className={labelText}>News articles</Text>
            <Text className={mutedText}>
                Explicitly search configured locale newsrooms for attributable reporting and opinion coverage.
            </Text>
            {billId === null ? (
                <Text testID="admin-news-articles-unsaved" className={errorText}>
                    Save this bill to retrieve news articles.
                </Text>
            ) : null}
            <View className="flex-row">
                <Pressable
                    testID="admin-news-articles-fetch"
                    variant="outline"
                    accessibilityLabel="Fetch articles"
                    disabled={billId === null || loading}
                    onPress={() => void fetchArticles()}
                >
                    <Text className={labelText}>{loading ? "Fetching articles..." : "Fetch articles"}</Text>
                </Pressable>
            </View>
            <ReceiptNotice status={receiptStatus} requestError={requestError} />
            {articles.length === 0 && receiptStatus === null ? (
                <Text testID="admin-news-articles-empty" className={mutedText}>
                    No news articles retrieved yet. Tap &quot;Fetch articles&quot; to search configured newsrooms.
                </Text>
            ) : null}
            {articles.map((article) => (
                <ArticleRow key={article.id} article={article} />
            ))}
        </View>
    );
};

export default NewsArticlesSection;
