import { ExternalLink } from "lucide-react";
import type { sway } from "sway";

import { cn } from "@/lib/utils";
import { Badge } from "app/frontend/components/ui/badge";
import { isSafeUrl } from "app/frontend/sway_utils/safeHref";

// @lat: [[news-web-testimony#News web testimony]]
// @lat: [[news-web-testimony#Why published opinion commentary sits alongside support and oppose reasoning]]
// @lat: [[news-web-testimony#Clear demarcation from legislative hearing testimony and organizational positions]]
// @lat: [[news-web-testimony#Attribution fidelity and secure citation navigation]]
// @lat: [[news-web-testimony#Multi-theme layout integration]]

interface IProps {
    testimonies?: sway.INewsArticleTestimony[];
    stance?: "support" | "oppose";
    variant?: "default" | "ballot" | "banner" | "cornerstore" | "monochrome" | "service-manual" | "swiss-grid";
    className?: string;
}

const getAttribution = (testimony: sway.INewsArticleTestimony): { authorByline: string; outletName: string } => {
    const authorByline = testimony.author_name
        ? `By ${testimony.author_name}`
        : testimony.outlet_name.toLowerCase().includes("editorial board")
          ? testimony.outlet_name
          : `${testimony.outlet_name} Editorial Board`;
    return {
        authorByline,
        outletName: testimony.outlet_name,
    };
};

const CitationLink: React.FC<{ testimony: sway.INewsArticleTestimony }> = ({ testimony }) => {
    const safe = isSafeUrl(testimony.url);
    const { outletName } = getAttribution(testimony);

    if (!safe) {
        return <span className="font-semibold text-foreground/80">{outletName}</span>;
    }

    return (
        <a
            href={testimony.url}
            target="_blank"
            rel="noopener noreferrer"
            className="group inline-flex items-center gap-1 font-semibold text-foreground/80 hover:text-primary hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring rounded-sm break-words"
        >
            <span>{outletName}</span>
            <ExternalLink
                className="size-3.5 shrink-0 self-center text-muted-foreground group-hover:text-primary"
                aria-hidden="true"
            />
            <span className="sr-only"> (opens in new tab)</span>
        </a>
    );
};

const NewsArticleTestimony: React.FC<IProps> = ({ testimonies, stance, variant = "default", className }) => {
    if (!testimonies || testimonies.length === 0) return null;

    const filtered = stance ? testimonies.filter((t) => t.stance === stance) : testimonies;

    if (filtered.length === 0) return null;

    if (variant === "ballot") {
        return (
            <ul className={cn("bal-orgs mt-4", className)}>
                {filtered.map((testimony) => {
                    const { authorByline } = getAttribution(testimony);
                    return (
                        <li key={testimony.id} className="bal-org" data-testid="news-article-testimony">
                            <span className="bal-org__stance">
                                {testimony.stance === "support" ? "For" : "Against"}
                            </span>
                            <div className="w-full space-y-1">
                                <div className="flex flex-wrap items-center gap-2">
                                    <h3 className="bal-org__name">{authorByline}</h3>
                                    <Badge variant="stamp" tone="warning">
                                        News commentary
                                    </Badge>
                                </div>
                                <p className="bal-org__summary text-sm leading-6 text-foreground/90">
                                    {testimony.argument}
                                </p>
                                <div className="flex items-center gap-2 pt-1 text-xs text-muted-foreground">
                                    <CitationLink testimony={testimony} />
                                </div>
                            </div>
                        </li>
                    );
                })}
            </ul>
        );
    }

    if (variant === "banner") {
        return (
            <div className={cn("bn-provisions mt-4", className)}>
                {filtered.map((testimony) => {
                    const { authorByline } = getAttribution(testimony);
                    return (
                        <article key={testimony.id} className="bn-prov" data-testid="news-article-testimony">
                            <div className="bn-num" aria-hidden="true">
                                {testimony.stance === "support" ? "+" : "-"}
                            </div>
                            <div className="w-full space-y-1">
                                <div className="flex flex-wrap items-center gap-2">
                                    <h3 className="text-base font-bold">{authorByline}</h3>
                                    <Badge variant="stamp" tone="warning">
                                        News commentary
                                    </Badge>
                                    {!stance && (
                                        <Badge
                                            variant="stamp"
                                            tone={testimony.stance === "support" ? "primary" : "neutral"}
                                        >
                                            {testimony.stance === "support" ? "Support" : "Oppose"}
                                        </Badge>
                                    )}
                                </div>
                                <p className="text-sm leading-6 text-foreground/90">{testimony.argument}</p>
                                <div className="flex items-center gap-2 pt-1 text-xs text-muted-foreground">
                                    <CitationLink testimony={testimony} />
                                </div>
                            </div>
                        </article>
                    );
                })}
            </div>
        );
    }

    if (variant === "cornerstore") {
        return (
            <ul className={cn("cs-orgs mt-4", className)}>
                {filtered.map((testimony) => {
                    const { authorByline } = getAttribution(testimony);
                    return (
                        <li key={testimony.id} className="cs-org" data-testid="news-article-testimony">
                            <span
                                className={`cs-org__stance cs-org__stance--${
                                    testimony.stance === "support" ? "for" : "against"
                                }`}
                            >
                                {testimony.stance === "support" ? "For" : "Against"}
                            </span>
                            <div className="w-full space-y-1">
                                <div className="flex flex-wrap items-center gap-2">
                                    <h3 className="cs-org__name">{authorByline}</h3>
                                    <Badge variant="stamp" tone="warning">
                                        News commentary
                                    </Badge>
                                </div>
                                <p className="cs-org__summary text-sm leading-6 text-foreground/90">
                                    {testimony.argument}
                                </p>
                                <div className="flex items-center gap-2 pt-1 text-xs text-muted-foreground">
                                    <CitationLink testimony={testimony} />
                                </div>
                            </div>
                        </li>
                    );
                })}
            </ul>
        );
    }

    if (variant === "monochrome") {
        return (
            <ul className={cn("mcb-orgs mt-4", className)}>
                {filtered.map((testimony) => {
                    const { authorByline } = getAttribution(testimony);
                    return (
                        <li key={testimony.id} className="mcb-org" data-testid="news-article-testimony">
                            <span className="mcb-org__stance font-mono">
                                {testimony.stance === "support" ? "For" : "Against"}
                            </span>
                            <div className="w-full space-y-1">
                                <div className="flex flex-wrap items-center gap-2">
                                    <h3 className="mcb-org__name font-mono">{authorByline}</h3>
                                    <Badge variant="stamp" tone="warning">
                                        News commentary
                                    </Badge>
                                </div>
                                <p className="mcb-org__summary text-sm leading-6 text-foreground/90">
                                    {testimony.argument}
                                </p>
                                <div className="flex items-center gap-2 pt-1 text-xs text-muted-foreground">
                                    <CitationLink testimony={testimony} />
                                </div>
                            </div>
                        </li>
                    );
                })}
            </ul>
        );
    }

    if (variant === "service-manual") {
        return (
            <ul className={cn("smb-orgs mt-4", className)}>
                {filtered.map((testimony) => {
                    const { authorByline } = getAttribution(testimony);
                    return (
                        <li key={testimony.id} className="smb-org" data-testid="news-article-testimony">
                            <span
                                className={`smb-org__stance smb-org__stance--${
                                    testimony.stance === "support" ? "for" : "against"
                                }`}
                            >
                                {testimony.stance === "support" ? "For" : "Against"}
                            </span>
                            <div className="w-full space-y-1">
                                <div className="flex flex-wrap items-center gap-2">
                                    <h3 className="smb-org__name">{authorByline}</h3>
                                    <Badge variant="stamp" tone="warning">
                                        News commentary
                                    </Badge>
                                </div>
                                <p className="smb-org__summary text-sm leading-6 text-foreground/90">
                                    {testimony.argument}
                                </p>
                                <div className="flex items-center gap-2 pt-1 text-xs text-muted-foreground">
                                    <CitationLink testimony={testimony} />
                                </div>
                            </div>
                        </li>
                    );
                })}
            </ul>
        );
    }

    if (variant === "swiss-grid") {
        return (
            <ul className={cn("sgb-orgs mt-4", className)}>
                {filtered.map((testimony) => {
                    const { authorByline } = getAttribution(testimony);
                    return (
                        <li key={testimony.id} className="sgb-org" data-testid="news-article-testimony">
                            <span className="sgb-org__stance">
                                {testimony.stance === "support" ? "For" : "Against"}
                            </span>
                            <div className="w-full space-y-1">
                                <div className="flex flex-wrap items-center gap-2">
                                    <h3 className="sgb-org__name">{authorByline}</h3>
                                    <Badge variant="stamp" tone="warning">
                                        News commentary
                                    </Badge>
                                </div>
                                <p className="sgb-org__summary text-sm leading-6 text-foreground/90">
                                    {testimony.argument}
                                </p>
                                <div className="flex items-center gap-2 pt-1 text-xs text-muted-foreground">
                                    <CitationLink testimony={testimony} />
                                </div>
                            </div>
                        </li>
                    );
                })}
            </ul>
        );
    }

    return (
        <div className={cn("space-y-4", className)}>
            {filtered.map((testimony) => {
                const { authorByline } = getAttribution(testimony);
                return (
                    <div
                        key={testimony.id}
                        data-neo-surface="true"
                        className="rounded-xl px-4 py-4"
                        data-testid="news-article-testimony"
                    >
                        <div className="flex flex-wrap items-center justify-between gap-2">
                            <p className="text-sm font-black text-foreground">{authorByline}</p>
                            <div className="flex items-center gap-1.5">
                                <Badge variant="stamp" tone="warning">
                                    News commentary
                                </Badge>
                                {!stance && (
                                    <Badge
                                        variant="stamp"
                                        tone={testimony.stance === "support" ? "primary" : "neutral"}
                                    >
                                        {testimony.stance === "support" ? "Support" : "Oppose"}
                                    </Badge>
                                )}
                            </div>
                        </div>
                        <p className="mt-2 text-sm leading-6 text-foreground/90">{testimony.argument}</p>
                        <div className="mt-3 flex items-center gap-2 text-xs text-muted-foreground">
                            <CitationLink testimony={testimony} />
                        </div>
                    </div>
                );
            })}
        </div>
    );
};

export default NewsArticleTestimony;
