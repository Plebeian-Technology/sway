import { ExternalLink } from "lucide-react";
import type { sway } from "sway";

import { cn } from "@/lib/utils";
import { Badge } from "app/frontend/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { formatDate } from "app/frontend/sway_utils/datetimes";
import { isSafeUrl } from "app/frontend/sway_utils/safeHref";

// @lat: [[news-web-links#Why approved news links sit outside summary and testimony]]
// @lat: [[news-web-links#URL scheme safety and external navigation]]
// @lat: [[news-web-links#Multi-theme presentation parity]]

interface IProps {
    articles?: sway.INewsArticle[];
    variant?: "default" | "ballot" | "banner" | "cornerstore" | "monochrome" | "service-manual" | "swiss-grid";
    className?: string;
}

const formatPublishedDate = (publishedAt: string | null): string | null => {
    if (!publishedAt) return null;
    try {
        const d = new Date(publishedAt);
        if (isNaN(d.getTime())) return null;
        return formatDate(d);
    } catch {
        return null;
    }
};

const ArticleItem: React.FC<{ article: sway.INewsArticle }> = ({ article }) => {
    const formattedDate = formatPublishedDate(article.published_at);
    const safe = isSafeUrl(article.url);

    return (
        <div className="space-y-1">
            <div className="flex items-start justify-between gap-2">
                {safe ? (
                    <a
                        href={article.url}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="group inline-flex items-baseline gap-1.5 font-bold text-foreground hover:text-primary hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring rounded-sm break-words"
                    >
                        <span>{article.title}</span>
                        <ExternalLink
                            className="size-3.5 shrink-0 self-center text-muted-foreground group-hover:text-primary"
                            aria-hidden="true"
                        />
                        <span className="sr-only"> (opens in new tab)</span>
                    </a>
                ) : (
                    <span className="font-bold text-foreground break-words">{article.title}</span>
                )}
            </div>

            <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-muted-foreground">
                <span className="font-semibold text-foreground/80">{article.outlet_name}</span>
                {article.author_name && (
                    <>
                        <span aria-hidden="true">&bull;</span>
                        <span>By {article.author_name}</span>
                    </>
                )}
                {formattedDate && (
                    <>
                        <span aria-hidden="true">&bull;</span>
                        <span>{formattedDate}</span>
                    </>
                )}
                <div className="flex flex-wrap items-center gap-1.5 ml-auto">
                    {article.match_kind === "direct" && (
                        <Badge variant="stamp" tone="primary">
                            Direct coverage
                        </Badge>
                    )}
                    {article.match_kind === "context" && (
                        <Badge variant="stamp" tone="neutral">
                            Context
                        </Badge>
                    )}
                    {article.article_kind === "op_ed" && (
                        <Badge variant="stamp" tone="warning">
                            Op-ed
                        </Badge>
                    )}
                    {article.article_kind === "editorial" && (
                        <Badge variant="stamp" tone="warning">
                            Editorial
                        </Badge>
                    )}
                </div>
            </div>
        </div>
    );
};

const RelatedNewsArticles: React.FC<IProps> = ({ articles, variant = "default", className }) => {
    if (!articles || articles.length === 0) return null;

    if (variant === "ballot") {
        return (
            <section className={cn("bal-section", className)} data-testid="related-news-articles">
                <h2 className="bal-sectionlabel">Related news</h2>
                <ul className="space-y-4 pt-2">
                    {articles.map((article) => (
                        <li key={article.id} className="bal-org">
                            <div className="w-full">
                                <ArticleItem article={article} />
                            </div>
                        </li>
                    ))}
                </ul>
            </section>
        );
    }

    if (variant === "banner") {
        return (
            <section className={cn("bn-section", className)} data-testid="related-news-articles">
                <div className="bn-eyebrow">Related news</div>
                <div className="space-y-4 pt-2">
                    {articles.map((article) => (
                        <article key={article.id} className="bn-prov">
                            <div className="w-full">
                                <ArticleItem article={article} />
                            </div>
                        </article>
                    ))}
                </div>
            </section>
        );
    }

    if (variant === "cornerstore") {
        return (
            <div className={cn("cs-card cs-card--wide", className)} data-testid="related-news-articles">
                <h2 className="cs-card__title">Related news</h2>
                <ul className="space-y-4 pt-2">
                    {articles.map((article) => (
                        <li key={article.id} className="cs-org">
                            <div className="w-full">
                                <ArticleItem article={article} />
                            </div>
                        </li>
                    ))}
                </ul>
            </div>
        );
    }

    if (variant === "monochrome") {
        return (
            <section className={cn("mcb-section", className)} data-testid="related-news-articles">
                <h2 className="mcb-sectionlabel">Related news</h2>
                <ul className="space-y-4 pt-2">
                    {articles.map((article) => (
                        <li key={article.id} className="mcb-article">
                            <div className="w-full">
                                <ArticleItem article={article} />
                            </div>
                        </li>
                    ))}
                </ul>
            </section>
        );
    }

    if (variant === "service-manual") {
        return (
            <section className={cn("smb-section", className)} data-testid="related-news-articles">
                <h2 className="smb-sectionlabel">Related news</h2>
                <ul className="space-y-4 pt-2">
                    {articles.map((article) => (
                        <li key={article.id} className="smb-article">
                            <div className="w-full">
                                <ArticleItem article={article} />
                            </div>
                        </li>
                    ))}
                </ul>
            </section>
        );
    }

    if (variant === "swiss-grid") {
        return (
            <section className={cn("sgb-row", className)} data-testid="related-news-articles">
                <h2 className="sgb-index">Related news</h2>
                <div className="sgb-content">
                    <ul className="space-y-4">
                        {articles.map((article) => (
                            <li key={article.id} className="sgb-article">
                                <div className="w-full">
                                    <ArticleItem article={article} />
                                </div>
                            </li>
                        ))}
                    </ul>
                </div>
            </section>
        );
    }

    return (
        <Card className={cn("bg-card/95", className)} data-testid="related-news-articles">
            <CardHeader>
                <CardTitle className="text-xl font-black">Related news</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
                <ul className="divide-y divide-border/60">
                    {articles.map((article) => (
                        <li key={article.id} className="py-3 first:pt-0 last:pb-0">
                            <ArticleItem article={article} />
                        </li>
                    ))}
                </ul>
            </CardContent>
        </Card>
    );
};

export default RelatedNewsArticles;
