import { router, usePage, usePoll } from "@inertiajs/react";
import * as React from "react";
import { useCallback, useState } from "react";
import { ROUTES } from "app/frontend/sway_constants/routes";
import type { IAdminBillNewsArticle, NewsArticleKind, NewsArticleStance } from "app/frontend/types/bill_creator";
import { Button } from "app/frontend/components/ui/button";
import { Badge } from "app/frontend/components/ui/badge";
import { isSafeUrl } from "app/frontend/sway_utils/safeHref";

export interface IBillCreatorNewsArticlesProps {
    billId?: number | null;
    newsArticles?: IAdminBillNewsArticle[];
    readOnly?: boolean;
}

interface IPageProps {
    news_articles?: IAdminBillNewsArticle[];
    receipt_status?: string | null;
    errors?: {
        news_article?: string;
        [key: string]: unknown;
    };
    [key: string]: unknown;
}

const POLL_INTERVAL_MS = 5000;

const extractNewsArticleError = (errors: unknown): string | null => {
    if (typeof errors === "string" && errors.trim().length > 0) {
        return errors.trim();
    }
    if (errors && typeof errors === "object" && "news_article" in errors) {
        const candidate = (errors as { news_article?: unknown }).news_article;
        if (typeof candidate === "string" && candidate.trim().length > 0) {
            return candidate.trim();
        }
    }
    return null;
};

// @lat: [[news-admin-ui#Explicit article retrieval]]
const NewsArticlesInFlightPoller: React.FC = () => {
    usePoll(POLL_INTERVAL_MS, { only: ["news_articles"] });
    return null;
};

// @lat: [[news-article-evidence#Article identity and bill association]]
const BillCreatorNewsArticles: React.FC<IBillCreatorNewsArticlesProps> = ({
    billId,
    newsArticles: propsArticles,
    readOnly = false,
}) => {
    const pageProps = usePage<IPageProps>().props;
    const articles = propsArticles ?? pageProps.news_articles ?? [];

    const [isFetching, setIsFetching] = useState<boolean>(false);
    const [receiptStatus, setReceiptStatus] = useState<string | null>(pageProps.receipt_status ?? null);
    const [receiptError, setReceiptError] = useState<string | null>(() => extractNewsArticleError(pageProps.errors));

    const [editingArticleId, setEditingArticleId] = useState<number | null>(null);
    const [manualText, setManualText] = useState<string>("");
    const [manualTextError, setManualTextError] = useState<string | null>(null);

    const [activeActionArticleId, setActiveActionArticleId] = useState<number | null>(null);

    const isPersistedBill = typeof billId === "number" && billId > 0;

    const handleFetchArticles = useCallback(() => {
        if (!isPersistedBill) return;

        setIsFetching(true);
        setReceiptStatus(null);
        setReceiptError(null);

        router.post(
            ROUTES.admin_bill_news_articles(billId),
            {},
            {
                preserveScroll: true,
                preserveState: true,
                onSuccess: (page) => {
                    setIsFetching(false);
                    const props = page.props as IPageProps | undefined;
                    const status = props?.receipt_status ?? "succeeded";
                    setReceiptStatus(status);
                    if (status === "failed") {
                        setReceiptError(extractNewsArticleError(props?.errors));
                    }
                    router.reload({ only: ["news_articles"] });
                },
                onError: (errors) => {
                    setIsFetching(false);
                    setReceiptStatus("failed");
                    setReceiptError(extractNewsArticleError(errors) ?? "Failed to retrieve news articles.");
                },
                onFinish: () => {
                    setIsFetching(false);
                },
            },
        );
    }, [billId, isPersistedBill]);

    const handleToggleApproval = useCallback(
        (article: IAdminBillNewsArticle) => {
            if (!isPersistedBill || readOnly) return;

            setActiveActionArticleId(article.id);
            router.patch(
                ROUTES.admin_bill_news_article(billId, article.id),
                { approved: !article.approved },
                {
                    preserveScroll: true,
                    preserveState: true,
                    onSuccess: () => {
                        router.reload({ only: ["news_articles"] });
                    },
                    onFinish: () => {
                        setActiveActionArticleId(null);
                    },
                },
            );
        },
        [billId, isPersistedBill, readOnly],
    );

    const handleChangeStance = useCallback(
        (article: IAdminBillNewsArticle, newStance: NewsArticleStance) => {
            if (!isPersistedBill || readOnly) return;

            setActiveActionArticleId(article.id);
            router.patch(
                ROUTES.admin_bill_news_article(billId, article.id),
                { stance: newStance ?? "" },
                {
                    preserveScroll: true,
                    preserveState: true,
                    onSuccess: () => {
                        router.reload({ only: ["news_articles"] });
                    },
                    onFinish: () => {
                        setActiveActionArticleId(null);
                    },
                },
            );
        },
        [billId, isPersistedBill, readOnly],
    );

    const handleChangeGenre = useCallback(
        (article: IAdminBillNewsArticle, newGenre: NewsArticleKind) => {
            if (!isPersistedBill || readOnly) return;

            setActiveActionArticleId(article.id);
            router.patch(
                ROUTES.admin_bill_news_article(billId, article.id),
                { article_kind: newGenre },
                {
                    preserveScroll: true,
                    preserveState: true,
                    onSuccess: () => {
                        router.reload({ only: ["news_articles"] });
                    },
                    onFinish: () => {
                        setActiveActionArticleId(null);
                    },
                },
            );
        },
        [billId, isPersistedBill, readOnly],
    );

    // @lat: [[news-review#Manual text enables synthesis without mandatory re-approval]]
    const handleSaveManualText = useCallback(
        (article: IAdminBillNewsArticle) => {
            if (!isPersistedBill || readOnly) return;

            const trimmed = manualText.trim();
            if (!trimmed) {
                setManualTextError("Article text cannot be blank.");
                return;
            }

            setManualTextError(null);
            setActiveActionArticleId(article.id);
            router.patch(
                ROUTES.admin_bill_news_article(billId, article.id),
                { text: trimmed },
                {
                    preserveScroll: true,
                    preserveState: true,
                    onSuccess: () => {
                        setEditingArticleId(null);
                        setManualText("");
                        router.reload({ only: ["news_articles"] });
                    },
                    onFinish: () => {
                        setActiveActionArticleId(null);
                    },
                },
            );
        },
        [billId, isPersistedBill, manualText, readOnly],
    );

    const isInFlight = isFetching || receiptStatus === "running" || receiptStatus === "queued";

    return (
        <div className="flex flex-col gap-4" data-testid="bill-creator-news-articles">
            {isInFlight && <NewsArticlesInFlightPoller />}

            <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                    <p className="text-sm text-muted-foreground">
                        Explicitly search configured locale newsrooms for attributable reporting and opinion coverage.
                    </p>
                    {!isPersistedBill && (
                        <p className="text-xs text-destructive">Select a persisted bill to retrieve news articles.</p>
                    )}
                </div>
                <Button
                    type="button"
                    variant="outline"
                    disabled={!isPersistedBill || isFetching || readOnly}
                    onClick={handleFetchArticles}
                    aria-label="Fetch articles"
                >
                    {isFetching ? "Fetching articles..." : "Fetch articles"}
                </Button>
            </div>

            {/* @lat: [[theme-tokens#Why components never pair raw Tailwind palette classes with dark:]] */}
            {receiptStatus === "succeeded" && (
                <div className="rounded-xl border-neo border-success bg-success/12 p-3 text-sm text-foreground">
                    Discovery completed successfully.
                </div>
            )}

            {receiptStatus === "no_matches" && (
                <div
                    data-testid="news-no-matches-notice"
                    className="rounded-xl border-neo border-border-strong bg-surface-2 p-3 text-sm text-muted-foreground"
                >
                    No matching articles found for this bill in configured newsroom sources.
                </div>
            )}

            {receiptStatus === "unsupported" && (
                <div
                    role="alert"
                    data-testid="news-unsupported-notice"
                    className="rounded-xl border-neo border-warning bg-warning/12 p-3 text-sm text-foreground"
                >
                    News discovery is not supported for this provider or locale.
                </div>
            )}

            {receiptStatus === "failed" && (
                <div
                    role="alert"
                    data-testid="news-failed-alert"
                    className="rounded-xl border-neo border-destructive bg-destructive/12 p-3 text-sm text-destructive"
                >
                    Failed to fetch articles from news sources. {receiptError && `(${receiptError})`}
                </div>
            )}

            {articles.length === 0 && !receiptStatus && (
                <p className="text-sm text-muted-foreground" data-testid="news-articles-empty">
                    No news articles retrieved yet. Click &quot;Fetch articles&quot; to search configured newsrooms.
                </p>
            )}

            {articles.length > 0 && (
                <div className="flex flex-col gap-4">
                    {articles.map((article) => {
                        const isActionBusy = activeActionArticleId === article.id;
                        const isEditingThis = editingArticleId === article.id;
                        const matchBadgeText = article.match_kind === "context" ? "Issue context" : "Direct coverage";

                        return (
                            <div
                                key={article.id}
                                className="flex flex-col gap-3 rounded-xl border-neo border-border-strong bg-card p-4 shadow-neo"
                                data-testid={`news-article-card-${article.id}`}
                            >
                                <div className="flex flex-wrap items-start justify-between gap-2">
                                    <div className="flex flex-col gap-1">
                                        <div className="flex flex-wrap items-center gap-2">
                                            <span className="font-semibold text-foreground">
                                                {article.source_name || "Unknown outlet"}
                                            </span>
                                            {article.domain && (
                                                <span className="text-xs text-muted-foreground">{article.domain}</span>
                                            )}
                                            <Badge variant="stamp" tone="neutral">
                                                {matchBadgeText}
                                            </Badge>
                                            {article.approved ? (
                                                <Badge
                                                    variant="stamp"
                                                    tone="success"
                                                    data-testid={`badge-approved-${article.id}`}
                                                >
                                                    Approved
                                                </Badge>
                                            ) : (
                                                <Badge
                                                    variant="stamp"
                                                    tone="neutral"
                                                    data-testid={`badge-unapproved-${article.id}`}
                                                >
                                                    Unapproved candidate
                                                </Badge>
                                            )}
                                        </div>
                                        {isSafeUrl(article.url) ? (
                                            <a
                                                href={article.url ?? undefined}
                                                target="_blank"
                                                rel="noopener noreferrer"
                                                className="text-base font-medium text-primary hover:underline"
                                            >
                                                {article.title || "Untitled article"}
                                            </a>
                                        ) : (
                                            <span className="text-base font-medium text-foreground">
                                                {article.title || "Untitled article"}
                                            </span>
                                        )}
                                        <div className="flex flex-wrap items-center gap-3 text-xs text-muted-foreground">
                                            {article.author && <span>by {article.author}</span>}
                                            {article.published_at && (
                                                <span>
                                                    {new Date(article.published_at).toLocaleDateString(undefined, {
                                                        year: "numeric",
                                                        month: "short",
                                                        day: "numeric",
                                                    })}
                                                </span>
                                            )}
                                        </div>
                                    </div>

                                    <div className="flex flex-wrap items-center gap-2">
                                        <Button
                                            type="button"
                                            size="sm"
                                            variant={article.approved ? "destructive" : "default"}
                                            disabled={!isPersistedBill || isActionBusy || readOnly}
                                            onClick={() => handleToggleApproval(article)}
                                            aria-label={
                                                article.approved
                                                    ? `Withdraw approval for ${article.title || "article"}`
                                                    : `Approve for this bill`
                                            }
                                        >
                                            {article.approved ? "Withdraw approval" : "Approve for this bill"}
                                        </Button>
                                    </div>
                                </div>

                                <div className="flex flex-wrap items-center gap-2 border-t border-border pt-3">
                                    {article.has_text ? (
                                        <>
                                            <Badge variant="stamp" tone="info" data-testid="badge-text-available">
                                                Text Available
                                            </Badge>
                                            {article.approved && (
                                                <Badge
                                                    variant="stamp"
                                                    tone="success"
                                                    data-testid="badge-eligible-for-synthesis"
                                                >
                                                    Eligible for synthesis
                                                </Badge>
                                            )}
                                            {article.text_origin && (
                                                <span className="text-xs text-muted-foreground">
                                                    Origin: {article.text_origin}
                                                </span>
                                            )}
                                        </>
                                    ) : (
                                        <div className="flex flex-col gap-1">
                                            <div className="flex items-center gap-2">
                                                <Badge variant="stamp" tone="warning" data-testid="badge-link-only">
                                                    Link-only
                                                </Badge>
                                                <span className="text-xs text-muted-foreground">
                                                    No article text available. This article will be included as an
                                                    external link on web and mobile. Cannot be cited in summary
                                                    synthesis until text is provided.
                                                </span>
                                            </div>
                                        </div>
                                    )}
                                </div>

                                {article.has_text && article.excerpt && (
                                    <div
                                        data-testid="article-excerpt"
                                        className="rounded-lg border border-border-soft bg-surface-2 p-2 text-xs text-foreground line-clamp-3"
                                    >
                                        {article.excerpt}
                                    </div>
                                )}

                                <div className="flex flex-wrap items-center justify-between gap-4 border-t border-border pt-3">
                                    <div className="flex flex-wrap items-center gap-4">
                                        <div className="flex items-center gap-1.5 text-xs">
                                            <label
                                                htmlFor={`genre-select-${article.id}`}
                                                className="text-muted-foreground"
                                            >
                                                Genre:
                                            </label>
                                            <select
                                                id={`genre-select-${article.id}`}
                                                aria-label={`Genre for ${article.title || "article"}`}
                                                className="rounded-md border-neo border-border-strong bg-input px-2 py-1 text-xs text-foreground"
                                                value={article.article_kind || "reporting"}
                                                disabled={!isPersistedBill || isActionBusy || readOnly}
                                                onChange={(e) =>
                                                    handleChangeGenre(article, e.target.value as NewsArticleKind)
                                                }
                                            >
                                                <option value="reporting">Reporting</option>
                                                <option value="op_ed">Op-Ed</option>
                                                <option value="editorial">Editorial</option>
                                                <option value="unknown">Unknown</option>
                                            </select>
                                        </div>

                                        <div className="flex items-center gap-1.5 text-xs">
                                            <label
                                                htmlFor={`stance-select-${article.id}`}
                                                className="text-muted-foreground"
                                            >
                                                Stance:
                                            </label>
                                            <select
                                                id={`stance-select-${article.id}`}
                                                aria-label={`Opinion stance for ${article.title || "article"}`}
                                                className="rounded-md border-neo border-border-strong bg-input px-2 py-1 text-xs text-foreground"
                                                value={article.stance || ""}
                                                disabled={!isPersistedBill || isActionBusy || readOnly}
                                                onChange={(e) =>
                                                    handleChangeStance(
                                                        article,
                                                        (e.target.value || null) as NewsArticleStance,
                                                    )
                                                }
                                            >
                                                <option value="">No stance</option>
                                                <option value="support">Support</option>
                                                <option value="oppose">Oppose</option>
                                            </select>
                                        </div>
                                    </div>

                                    <div>
                                        {!isEditingThis ? (
                                            <Button
                                                type="button"
                                                variant="ghost"
                                                size="sm"
                                                className="text-xs"
                                                aria-label={`Add text for article ${article.id}`}
                                                disabled={!isPersistedBill || isActionBusy || readOnly}
                                                onClick={() => {
                                                    setEditingArticleId(article.id);
                                                    setManualText("");
                                                    setManualTextError(null);
                                                }}
                                            >
                                                {article.has_text ? "Replace text" : "Add text"}
                                            </Button>
                                        ) : (
                                            <Button
                                                type="button"
                                                variant="ghost"
                                                size="sm"
                                                className="text-xs"
                                                onClick={() => {
                                                    setEditingArticleId(null);
                                                    setManualText("");
                                                    setManualTextError(null);
                                                }}
                                            >
                                                Cancel
                                            </Button>
                                        )}
                                    </div>
                                </div>

                                {isEditingThis && (
                                    <div className="flex flex-col gap-2 rounded-lg border-neo border-border-strong bg-surface-2 p-3">
                                        <label
                                            htmlFor={`manual-text-input-${article.id}`}
                                            className="text-xs font-medium text-foreground"
                                        >
                                            Manual article text
                                        </label>
                                        <textarea
                                            id={`manual-text-input-${article.id}`}
                                            aria-label="Manual article text"
                                            className="min-h-[100px] w-full rounded-md border-neo border-border-strong bg-input p-2 text-xs text-foreground"
                                            placeholder="Paste full article text for synthesis..."
                                            value={manualText}
                                            onChange={(e) => setManualText(e.target.value)}
                                        />
                                        {manualTextError && (
                                            <p className="text-xs text-destructive">{manualTextError}</p>
                                        )}
                                        <div className="flex justify-end gap-2">
                                            <Button
                                                type="button"
                                                size="sm"
                                                disabled={isActionBusy}
                                                onClick={() => handleSaveManualText(article)}
                                                aria-label="Save article text"
                                            >
                                                Save article text
                                            </Button>
                                        </div>
                                    </div>
                                )}
                            </div>
                        );
                    })}
                </div>
            )}
        </div>
    );
};

export default BillCreatorNewsArticles;
