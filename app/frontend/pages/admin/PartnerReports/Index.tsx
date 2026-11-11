// @lat: [[partner-article-engagement#Administrative interface]]
import { Link, usePoll } from "@inertiajs/react";
import { ExternalLink, MousePointer, Newspaper, ShieldAlert, Users, Vote } from "lucide-react";
import React from "react";

import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "app/frontend/components/ui/table";
import { ROUTES } from "app/frontend/sway_constants";
import { isSafeUrl } from "app/frontend/sway_utils/safeHref";

export interface IArticleReport {
    id: number;
    bill_id: number;
    bill_title?: string | null;
    article_title: string;
    article_url: string;
    published_at: string | null;
    clicks_count: number;
    registrations_count: number;
    votes_count: number;
    sentiment_suppressed: boolean;
    pro_votes_count: number | null;
    con_votes_count: number | null;
}

export interface IPartnerReport {
    partner_slug: string;
    partner_name: string;
    articles_count: number;
    bills_count: number;
    total_clicks: number;
    total_registrations: number;
    total_votes: number;
    pro_percentage: number | null;
    con_percentage: number | null;
    sentiment_suppressed?: boolean;
    articles: IArticleReport[];
}

interface IProps {
    reports?: IPartnerReport[];
    report?: IPartnerReport;
}

const formatDate = (dateStr: string | null): string => {
    if (!dateStr) return "N/A";
    try {
        const d = new Date(dateStr);
        return isNaN(d.getTime())
            ? dateStr
            : d.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
    } catch {
        return dateStr;
    }
};

const PartnerReportsIndex: React.FC<IProps> = ({ reports, report }) => {
    usePoll(15000, { only: ["reports", "report"] });

    const isSingleView = Boolean(report);
    const activePartners: IPartnerReport[] = report ? [report] : (reports ?? []);

    const allArticles: Array<IArticleReport & { partner_name?: string }> =
        isSingleView && report
            ? report.articles.map((a) => ({ ...a, partner_name: report.partner_name }))
            : (reports ?? []).flatMap((r) => r.articles.map((a) => ({ ...a, partner_name: r.partner_name })));

    const totalClicks = activePartners.reduce((acc, p) => acc + p.total_clicks, 0);
    const totalRegistrations = activePartners.reduce((acc, p) => acc + p.total_registrations, 0);
    const totalVotes = activePartners.reduce((acc, p) => acc + p.total_votes, 0);
    const totalArticlesCount = activePartners.reduce((acc, p) => acc + p.articles_count, 0);

    return (
        <div className="mx-auto w-full max-w-6xl space-y-6 px-4 py-6 sm:px-6 overflow-x-hidden">
            <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                <div className="space-y-1">
                    <div className="flex items-center gap-2 text-sm text-muted-foreground">
                        <Link href={ROUTES.admin} className="min-h-[44px] inline-flex items-center hover:underline">
                            Admin
                        </Link>
                        <span>/</span>
                        {isSingleView ? (
                            <>
                                <Link
                                    href="/admin/partner_reports"
                                    className="min-h-[44px] inline-flex items-center hover:underline"
                                >
                                    Partner Reports
                                </Link>
                                <span>/</span>
                                <span className="font-medium text-foreground">{report?.partner_name}</span>
                            </>
                        ) : (
                            <span className="font-medium text-foreground">Partner Reports</span>
                        )}
                    </div>
                    <h1 className="text-2xl font-bold tracking-tight sm:text-3xl">
                        {isSingleView && report ? report.partner_name : "Partner Reports"}
                    </h1>
                    <p className="text-sm text-muted-foreground">
                        {isSingleView && report
                            ? `Engagement metrics, voter conversion, and article coverage for ${report.partner_name} (${report.partner_slug}).`
                            : "Track newsroom partner article engagement, voter reach, and civic conversion."}
                    </p>
                </div>

                {isSingleView && (
                    <div className="flex items-center gap-2">
                        <Button variant="outline" size="sm" asChild className="min-h-[44px]">
                            <Link href="/admin/partner_reports">← All Partners</Link>
                        </Button>
                    </div>
                )}
            </div>

            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
                <Card>
                    <CardHeader className="flex flex-row items-center justify-between pb-2">
                        <CardTitle className="text-sm font-medium text-muted-foreground">
                            {isSingleView ? "Articles & Bills" : "Total Articles"}
                        </CardTitle>
                        <Newspaper className="h-4 w-4 text-muted-foreground" />
                    </CardHeader>
                    <CardContent>
                        <div className="text-2xl font-bold">{totalArticlesCount}</div>
                        <p className="text-xs text-muted-foreground">
                            {isSingleView && report
                                ? `Across ${report.bills_count} distinct bills`
                                : `Across ${activePartners.length} partner newsrooms`}
                        </p>
                    </CardContent>
                </Card>

                <Card>
                    <CardHeader className="flex flex-row items-center justify-between pb-2">
                        <CardTitle className="text-sm font-medium text-muted-foreground">Total Clicks</CardTitle>
                        <MousePointer className="h-4 w-4 text-muted-foreground" />
                    </CardHeader>
                    <CardContent>
                        <div className="text-2xl font-bold">{totalClicks.toLocaleString()}</div>
                        <p className="text-xs text-muted-foreground">Inbound reader referrals from embeds</p>
                    </CardContent>
                </Card>

                <Card>
                    <CardHeader className="flex flex-row items-center justify-between pb-2">
                        <CardTitle className="text-sm font-medium text-muted-foreground">Registrations</CardTitle>
                        <Users className="h-4 w-4 text-muted-foreground" />
                    </CardHeader>
                    <CardContent>
                        <div className="text-2xl font-bold">{totalRegistrations.toLocaleString()}</div>
                        <p className="text-xs text-muted-foreground">
                            {totalClicks > 0
                                ? `${((totalRegistrations / totalClicks) * 100).toFixed(1)}% click-to-register conversion`
                                : "Verified constituent accounts created"}
                        </p>
                    </CardContent>
                </Card>

                <Card>
                    <CardHeader className="flex flex-row items-center justify-between pb-2">
                        <CardTitle className="text-sm font-medium text-muted-foreground">Votes Cast</CardTitle>
                        <Vote className="h-4 w-4 text-muted-foreground" />
                    </CardHeader>
                    <CardContent>
                        <div className="text-2xl font-bold">{totalVotes.toLocaleString()}</div>
                        <div className="mt-1">
                            {isSingleView && report && (report.sentiment_suppressed ?? report.total_votes < 5) ? (
                                <Badge
                                    variant="outline"
                                    className="border-amber-500/30 bg-amber-500/10 text-amber-600 dark:text-amber-400"
                                >
                                    Suppressed (k &lt; 5)
                                </Badge>
                            ) : isSingleView && report && report.pro_percentage !== null ? (
                                <p className="text-xs text-muted-foreground">
                                    {report.pro_percentage}% Pro / {report.con_percentage}% Con
                                </p>
                            ) : (
                                <p className="text-xs text-muted-foreground">Constituent votes on covered bills</p>
                            )}
                        </div>
                    </CardContent>
                </Card>
            </div>

            {!isSingleView && (
                <Card>
                    <CardHeader>
                        <CardTitle className="text-lg">Partner Newsrooms</CardTitle>
                        <CardDescription>
                            Aggregated metrics and privacy-preserving sentiment for participating publishers.
                        </CardDescription>
                    </CardHeader>
                    <CardContent className="overflow-x-auto">
                        <Table>
                            <TableHeader>
                                <TableRow>
                                    <TableHead>Partner</TableHead>
                                    <TableHead className="text-right">Articles</TableHead>
                                    <TableHead className="text-right">Bills</TableHead>
                                    <TableHead className="text-right">Clicks</TableHead>
                                    <TableHead className="text-right">Registrations</TableHead>
                                    <TableHead className="text-right">Votes</TableHead>
                                    <TableHead className="text-center">Sentiment</TableHead>
                                    <TableHead className="text-right">Action</TableHead>
                                </TableRow>
                            </TableHeader>
                            <TableBody>
                                {activePartners.length === 0 ? (
                                    <TableRow>
                                        <TableCell colSpan={8} className="text-center py-6 text-muted-foreground">
                                            No partner newsroom data recorded yet.
                                        </TableCell>
                                    </TableRow>
                                ) : (
                                    activePartners.map((partner) => {
                                        const isSuppressed = partner.sentiment_suppressed ?? partner.total_votes < 5;
                                        return (
                                            <TableRow key={partner.partner_slug}>
                                                <TableCell>
                                                    <div className="font-semibold">{partner.partner_name}</div>
                                                    <div className="text-xs text-muted-foreground font-mono">
                                                        {partner.partner_slug}
                                                    </div>
                                                </TableCell>
                                                <TableCell className="text-right">{partner.articles_count}</TableCell>
                                                <TableCell className="text-right">{partner.bills_count}</TableCell>
                                                <TableCell className="text-right">
                                                    {partner.total_clicks.toLocaleString()}
                                                </TableCell>
                                                <TableCell className="text-right">
                                                    {partner.total_registrations.toLocaleString()}
                                                </TableCell>
                                                <TableCell className="text-right font-medium">
                                                    {partner.total_votes.toLocaleString()}
                                                </TableCell>
                                                <TableCell className="text-center">
                                                    {isSuppressed ? (
                                                        <Badge
                                                            variant="outline"
                                                            className="border-amber-500/30 bg-amber-500/10 text-amber-600 dark:text-amber-400"
                                                        >
                                                            Suppressed (k &lt; 5)
                                                        </Badge>
                                                    ) : partner.pro_percentage !== null ? (
                                                        <span className="text-sm font-medium">
                                                            {partner.pro_percentage}% Pro / {partner.con_percentage}%
                                                            Con
                                                        </span>
                                                    ) : (
                                                        <span className="text-xs text-muted-foreground">N/A</span>
                                                    )}
                                                </TableCell>
                                                <TableCell className="text-right">
                                                    <Button variant="ghost" size="sm" asChild className="min-h-[44px]">
                                                        <Link href={`/admin/partner_reports/${partner.partner_slug}`}>
                                                            Details →
                                                        </Link>
                                                    </Button>
                                                </TableCell>
                                            </TableRow>
                                        );
                                    })
                                )}
                            </TableBody>
                        </Table>
                    </CardContent>
                </Card>
            )}

            <Card>
                <CardHeader>
                    <div className="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
                        <div>
                            <CardTitle className="text-lg">Covered Articles</CardTitle>
                            <CardDescription>
                                Individual articles embedding Sway widgets with attribution, conversion, and k-anonymity
                                sentiment.
                            </CardDescription>
                        </div>
                        <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
                            <ShieldAlert className="h-3.5 w-3.5 text-amber-500" />
                            <span>k &lt; 5 votes suppresses sentiment to protect voter privacy</span>
                        </div>
                    </div>
                </CardHeader>
                <CardContent className="overflow-x-auto">
                    <Table>
                        <TableHeader>
                            <TableRow>
                                <TableHead>Article Title</TableHead>
                                {!isSingleView && <TableHead>Partner</TableHead>}
                                <TableHead>Published</TableHead>
                                <TableHead className="text-right">Clicks</TableHead>
                                <TableHead className="text-right">Registrations</TableHead>
                                <TableHead className="text-right">Votes</TableHead>
                                <TableHead className="text-center">Sentiment</TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                            {allArticles.length === 0 ? (
                                <TableRow>
                                    <TableCell
                                        colSpan={isSingleView ? 6 : 7}
                                        className="text-center py-6 text-muted-foreground"
                                    >
                                        No articles recorded for this partner yet.
                                    </TableCell>
                                </TableRow>
                            ) : (
                                allArticles.map((article) => {
                                    const isArticleSuppressed = article.sentiment_suppressed ?? article.votes_count < 5;
                                    return (
                                        <TableRow key={article.id}>
                                            <TableCell className="max-w-md">
                                                {isSafeUrl(article.article_url) ? (
                                                    <a
                                                        href={article.article_url}
                                                        target="_blank"
                                                        rel="noopener noreferrer"
                                                        className="inline-flex items-center gap-1 font-medium hover:underline text-foreground"
                                                    >
                                                        <span>{article.article_title}</span>
                                                        <ExternalLink className="h-3 w-3 text-muted-foreground shrink-0" />
                                                    </a>
                                                ) : (
                                                    <span className="font-medium text-foreground">
                                                        {article.article_title}
                                                    </span>
                                                )}
                                                {article.bill_title && (
                                                    <div className="text-xs text-muted-foreground line-clamp-1 mt-0.5">
                                                        Bill: {article.bill_title}
                                                    </div>
                                                )}
                                            </TableCell>
                                            {!isSingleView && (
                                                <TableCell className="text-sm font-medium">
                                                    {article.partner_name}
                                                </TableCell>
                                            )}
                                            <TableCell className="text-sm text-muted-foreground whitespace-nowrap">
                                                {formatDate(article.published_at)}
                                            </TableCell>
                                            <TableCell className="text-right">
                                                {article.clicks_count.toLocaleString()}
                                            </TableCell>
                                            <TableCell className="text-right">
                                                {article.registrations_count.toLocaleString()}
                                            </TableCell>
                                            <TableCell className="text-right font-medium">
                                                {article.votes_count.toLocaleString()}
                                            </TableCell>
                                            <TableCell className="text-center whitespace-nowrap">
                                                {isArticleSuppressed ? (
                                                    <Badge
                                                        variant="outline"
                                                        className="border-amber-500/30 bg-amber-500/10 text-amber-600 dark:text-amber-400 text-xs"
                                                    >
                                                        Suppressed (k &lt; 5)
                                                    </Badge>
                                                ) : (
                                                    <span className="text-xs font-medium">
                                                        {article.pro_votes_count ?? 0} Pro /{" "}
                                                        {article.con_votes_count ?? 0} Con
                                                    </span>
                                                )}
                                            </TableCell>
                                        </TableRow>
                                    );
                                })
                            )}
                        </TableBody>
                    </Table>
                </CardContent>
            </Card>
        </div>
    );
};

export default PartnerReportsIndex;
