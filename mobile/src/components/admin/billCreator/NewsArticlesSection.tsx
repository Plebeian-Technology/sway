// @lat: [[mobile-bill-creator#Sections#The news articles section]]
import React, { useState } from "react";
import { Linking, Text, TextInput, View } from "react-native";

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
    article_kind: string | null;
    stance: string | null;
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

const POLL_INTERVAL_MS = 5000;
const IN_FLIGHT_STATUSES = ["queued", "running"];

const GENRES = [
    { value: "reporting", label: "Reporting" },
    { value: "op_ed", label: "Op-Ed" },
    { value: "editorial", label: "Editorial" },
    { value: "unknown", label: "Unknown" },
];

const STANCES = [
    { value: "", testKey: "none", label: "No stance" },
    { value: "support", testKey: "support", label: "Support" },
    { value: "oppose", testKey: "oppose", label: "Oppose" },
];

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

interface IArticleReviewProps {
    billId: number;
    article: NewsArticle;
    refresh: () => Promise<void>;
}

// @lat: [[mobile-bill-creator#Sections#The news articles section#Reviewing an article]]
const ArticleReview: React.FC<IArticleReviewProps> = ({ billId, article, refresh }) => {
    const testID = `admin-news-article-${article.id}`;
    const { run, loading, errorMessage } = useAdminMutation<NewsArticle>(
        "patch",
        Routes.adminBillNewsArticle(billId, article.id),
    );
    const [editingText, setEditingText] = useState(false);
    const [manualText, setManualText] = useState("");
    const [manualTextError, setManualTextError] = useState<string | null>(null);

    const review = async (body: Record<string, unknown>) => {
        const result = await run(body);
        if (result === undefined) return false;
        await refresh();
        return true;
    };

    const toggleTextEditor = () => {
        setEditingText(!editingText);
        setManualText("");
        setManualTextError(null);
    };

    const saveManualText = async () => {
        const trimmed = manualText.trim();
        if (!trimmed) {
            setManualTextError("Article text cannot be blank.");
            return;
        }
        setManualTextError(null);
        if (await review({ text: trimmed })) {
            setEditingText(false);
            setManualText("");
        }
    };

    const articleName = article.title || "article";
    const genre = article.article_kind || "reporting";
    const stance = article.stance || "";

    return (
        <View className="gap-2 border-t border-border-light dark:border-border-dark pt-2">
            <View className="flex-row">
                <Pressable
                    testID={`${testID}-approve`}
                    variant={article.approved ? "destructive" : "default"}
                    disabled={loading}
                    accessibilityLabel={
                        article.approved ? `Withdraw approval for ${articleName}` : "Approve for this bill"
                    }
                    onPress={() => void review({ approved: !article.approved })}
                >
                    <Text className={labelText}>
                        {article.approved ? "Withdraw approval" : "Approve for this bill"}
                    </Text>
                </Pressable>
            </View>
            <Text className={mutedText}>Genre:</Text>
            <View className="flex-row flex-wrap gap-2">
                {GENRES.map((option) => (
                    <Pressable
                        key={option.value}
                        testID={`${testID}-genre-${option.value}`}
                        variant={genre === option.value ? "default" : "outline"}
                        accessibilityRole="radio"
                        accessibilityState={{ selected: genre === option.value }}
                        accessibilityLabel={`Genre for ${articleName}: ${option.label}`}
                        disabled={loading}
                        onPress={() => {
                            if (genre !== option.value) void review({ article_kind: option.value });
                        }}
                    >
                        <Text className={labelText}>{option.label}</Text>
                    </Pressable>
                ))}
            </View>
            <Text className={mutedText}>Stance:</Text>
            <View className="flex-row flex-wrap gap-2">
                {STANCES.map((option) => (
                    <Pressable
                        key={option.testKey}
                        testID={`${testID}-stance-${option.testKey}`}
                        variant={stance === option.value ? "default" : "outline"}
                        accessibilityRole="radio"
                        accessibilityState={{ selected: stance === option.value }}
                        accessibilityLabel={`Opinion stance for ${articleName}: ${option.label}`}
                        disabled={loading}
                        onPress={() => {
                            if (stance !== option.value) void review({ stance: option.value });
                        }}
                    >
                        <Text className={labelText}>{option.label}</Text>
                    </Pressable>
                ))}
            </View>
            <View className="flex-row">
                <Pressable
                    testID={`${testID}-edit-text`}
                    variant="ghost"
                    disabled={!editingText && loading}
                    accessibilityLabel={editingText ? "Cancel" : `Add text for article ${article.id}`}
                    onPress={toggleTextEditor}
                >
                    <Text className={labelText}>
                        {editingText ? "Cancel" : article.has_text ? "Replace text" : "Add text"}
                    </Text>
                </Pressable>
            </View>
            {editingText ? (
                <View className="gap-2">
                    <Text className={labelText}>Manual article text</Text>
                    <TextInput
                        testID={`${testID}-manual-text`}
                        accessibilityLabel="Manual article text"
                        placeholder="Paste full article text for synthesis..."
                        multiline
                        value={manualText}
                        onChangeText={setManualText}
                        className={`min-h-24 rounded-lg border border-border-light dark:border-border-dark p-3 ${bodyText}`}
                    />
                    {manualTextError ? (
                        <Text testID={`${testID}-manual-text-error`} className={errorText}>
                            {manualTextError}
                        </Text>
                    ) : null}
                    <View className="flex-row">
                        <Pressable
                            testID={`${testID}-save-text`}
                            disabled={loading}
                            accessibilityLabel="Save article text"
                            onPress={() => void saveManualText()}
                        >
                            <Text className={labelText}>Save article text</Text>
                        </Pressable>
                    </View>
                </View>
            ) : null}
            {errorMessage ? (
                <Text testID={`${testID}-review-error`} accessibilityRole="alert" className={errorText}>
                    {errorMessage}
                </Text>
            ) : null}
        </View>
    );
};

interface IArticleRowProps {
    billId: number | null;
    article: NewsArticle;
    refresh: () => Promise<void>;
}

const ArticleRow: React.FC<IArticleRowProps> = ({ billId, article, refresh }) => {
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
            {billId !== null ? <ArticleReview billId={billId} article={article} refresh={refresh} /> : null}
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
    const [fetchedFrom, setFetchedFrom] = useState<BillCreatorProps | null>(null);
    const [answer, setAnswer] = useState<Discovery | null>(null);

    const isCurrent = fetchedFrom === data;
    const refusal = discoveryFrom(errorBody);
    const requestError = loading ? null : refusal ? (refusal.error ?? null) : errorMessage;
    const answered = refusal ?? (isCurrent ? answer : null);

    let receiptStatus: string | null = (data.receipt_status as string | null | undefined) ?? null;
    if (loading) receiptStatus = null;
    else if (answered !== null) receiptStatus = answered.receipt_status;
    else if (requestError !== null) receiptStatus = "failed";

    const articles =
        (isCurrent ? answered?.articles : undefined) ?? (data.news_articles as NewsArticle[] | undefined) ?? [];

    usePolling(refresh, receiptStatus !== null && IN_FLIGHT_STATUSES.includes(receiptStatus), POLL_INTERVAL_MS);

    const fetchArticles = async () => {
        setAnswer(null);
        setFetchedFrom(data);
        const result = await run({});
        if (result) setAnswer(result);
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
                <ArticleRow key={article.id} billId={billId} article={article} refresh={refresh} />
            ))}
        </View>
    );
};

export default NewsArticlesSection;
