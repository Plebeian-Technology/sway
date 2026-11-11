// @lat: [[registration-funnel-telemetry#Admin registration funnel dashboard]]
import { Link, router, usePoll } from "@inertiajs/react";
import { AlertCircle, Bot, CheckCircle2, Clock, Filter, Percent, Share2, Users, Vote, X } from "lucide-react";
import React, { useState } from "react";

import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { Progress } from "app/frontend/components/ui/progress";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "app/frontend/components/ui/table";
import { ROUTES } from "app/frontend/sway_constants";
import { cn } from "@/lib/utils";

export interface IFunnelStep {
    step: string;
    label: string;
    visitor_count: number;
    step_conversion_rate: number;
    drop_off_count: number;
    drop_off_rate: number;
    conversion_rate_from_start: number;
}

export interface IFrictionPoint {
    from_step: string;
    to_step: string;
    label: string;
    drop_off_count: number;
    drop_off_rate: number;
    rank_by_count: number;
    rank_by_rate: number;
}

export interface IAttributionBreakdown {
    source: string;
    visitors_count: number;
    registrations_count: number;
    votes_count: number;
    conversion_rate: number;
    vote_rate: number;
}

export interface ILatencyMetrics {
    sample_count: number;
    avg_seconds: number;
    median_seconds: number;
    p95_seconds: number;
    min_seconds: number;
    max_seconds: number;
}

export interface ITimeRangeOption {
    id: string;
    label: string;
}

export type TFunnelTraffic = "humans" | "bots" | "all";

export interface ITrafficOption {
    id: TFunnelTraffic;
    label: string;
}

export interface IFunnelData {
    time_range: string;
    filter_attribution_key: string | null;
    steps: IFunnelStep[];
    overall_conversion_rate: number;
    friction_points: IFrictionPoint[];
    attributions: IAttributionBreakdown[];
    latency: ILatencyMetrics;
    time_ranges: ITimeRangeOption[];
    traffic: TFunnelTraffic;
    traffic_options: ITrafficOption[];
    bot_visitor_count: number;
}

interface IProps {
    funnel: IFunnelData;
}

const RegistrationFunnelIndex: React.FC<IProps> = ({ funnel }) => {
    usePoll(15000, { only: ["funnel"] });

    const [rankBy, setRankBy] = useState<"count" | "rate">("count");

    const visitFunnel = (params: { time_range: string; attribution_key: string | null; traffic: TFunnelTraffic }) => {
        router.get(
            ROUTES.admin_registration_funnel,
            {
                time_range: params.time_range,
                attribution_key: params.attribution_key || undefined,
                traffic: params.traffic === "humans" ? undefined : params.traffic,
            },
            { preserveState: true, preserveScroll: true },
        );
    };

    const currentTraffic: TFunnelTraffic = funnel?.traffic ?? "humans";

    const handleTimeRangeChange = (rangeId: string) => {
        visitFunnel({ time_range: rangeId, attribution_key: funnel.filter_attribution_key, traffic: currentTraffic });
    };

    const handleAttributionFilter = (source: string | null) => {
        visitFunnel({ time_range: funnel.time_range, attribution_key: source, traffic: currentTraffic });
    };

    const handleTrafficChange = (traffic: TFunnelTraffic) => {
        visitFunnel({ time_range: funnel.time_range, attribution_key: funnel.filter_attribution_key, traffic });
    };

    const sortedFrictionPoints = [...(funnel?.friction_points ?? [])].sort((a, b) =>
        rankBy === "count" ? a.rank_by_count - b.rank_by_count : a.rank_by_rate - b.rank_by_rate,
    );

    const steps = funnel?.steps ?? [];
    const landingVisitors = steps.find((s) => s.step === "landing")?.visitor_count || 0;
    const completedRegistrations =
        steps.find((s) => s.step === "registration_completed" || s.step === "geocoding_completed")?.visitor_count || 0;
    const firstVotes = steps.find((s) => s.step === "first_vote_cast")?.visitor_count || 0;

    return (
        <div className="mx-auto w-full max-w-6xl space-y-6 px-4 py-6 sm:px-6 overflow-x-hidden">
            <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                <div className="space-y-1">
                    <div className="flex items-center gap-2 text-sm text-muted-foreground">
                        <Link href={ROUTES.admin} className="min-h-[44px] inline-flex items-center hover:underline">
                            Admin
                        </Link>
                        <span>/</span>
                        <span className="font-medium text-foreground">Registration Funnel</span>
                    </div>
                    <h1 className="text-2xl font-bold tracking-tight sm:text-3xl">Registration Funnel</h1>
                    <p className="text-sm text-muted-foreground">
                        Self-hosted telemetry tracking step-by-step conversion, drop-off friction, and async geocoding
                        latency.
                    </p>
                </div>

                <div className="flex flex-wrap items-center gap-2">
                    {funnel?.time_ranges?.map((range) => {
                        const isActive = funnel.time_range === range.id;
                        return (
                            <Button
                                key={range.id}
                                variant={isActive ? "default" : "outline"}
                                size="sm"
                                onClick={() => handleTimeRangeChange(range.id)}
                                className="min-h-[44px] px-4 font-medium"
                            >
                                {range.label}
                            </Button>
                        );
                    })}
                </div>
            </div>

            <div className="flex flex-wrap items-center justify-between gap-3">
                <div className="flex flex-wrap items-center gap-2">
                    {funnel?.traffic_options?.map((option) => {
                        const isActive = currentTraffic === option.id;
                        return (
                            <Button
                                key={option.id}
                                variant={isActive ? "default" : "outline"}
                                size="sm"
                                aria-pressed={isActive}
                                onClick={() => handleTrafficChange(option.id)}
                                className="min-h-[44px] px-4 font-medium"
                            >
                                {option.label}
                            </Button>
                        );
                    })}
                </div>
                <div className="flex items-center gap-2 text-sm text-muted-foreground">
                    <Bot className="h-4 w-4 shrink-0" />
                    <span>
                        {currentTraffic === "humans" ? "Bot visitors filtered out: " : "Bot visitors in range: "}
                        <strong className="font-semibold text-foreground">
                            {(funnel?.bot_visitor_count ?? 0).toLocaleString()}
                        </strong>
                    </span>
                </div>
            </div>

            {funnel?.filter_attribution_key && (
                <div className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-primary/20 bg-primary/5 p-4">
                    <div className="flex items-center gap-2 text-sm">
                        <Filter className="h-4 w-4 text-primary shrink-0" />
                        <span>
                            Filtered by referral source:{" "}
                            <strong className="font-semibold">{funnel.filter_attribution_key}</strong>
                        </span>
                    </div>
                    <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => handleAttributionFilter(null)}
                        className="min-h-[44px] gap-1 text-sm text-muted-foreground hover:text-foreground"
                    >
                        <X className="h-4 w-4" />
                        Clear Filter
                    </Button>
                </div>
            )}

            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
                <Card>
                    <CardHeader className="flex flex-row items-center justify-between pb-2">
                        <CardTitle className="text-sm font-medium text-muted-foreground">Landing Visitors</CardTitle>
                        <Users className="h-4 w-4 text-muted-foreground" />
                    </CardHeader>
                    <CardContent>
                        <div className="text-2xl font-bold">{landingVisitors.toLocaleString()}</div>
                        <p className="text-xs text-muted-foreground">Initial entry impressions</p>
                    </CardContent>
                </Card>

                <Card>
                    <CardHeader className="flex flex-row items-center justify-between pb-2">
                        <CardTitle className="text-sm font-medium text-muted-foreground">
                            Completed Registrations
                        </CardTitle>
                        <CheckCircle2 className="h-4 w-4 text-emerald-600" />
                    </CardHeader>
                    <CardContent>
                        <div className="text-2xl font-bold">{completedRegistrations.toLocaleString()}</div>
                        <p className="text-xs text-muted-foreground">
                            {landingVisitors > 0
                                ? `${((completedRegistrations / landingVisitors) * 100).toFixed(1)}% of visitors`
                                : "0%"}
                        </p>
                    </CardContent>
                </Card>

                <Card>
                    <CardHeader className="flex flex-row items-center justify-between pb-2">
                        <CardTitle className="text-sm font-medium text-muted-foreground">First Votes Cast</CardTitle>
                        <Vote className="h-4 w-4 text-primary" />
                    </CardHeader>
                    <CardContent>
                        <div className="text-2xl font-bold">{firstVotes.toLocaleString()}</div>
                        <p className="text-xs text-muted-foreground">Activated civic participants</p>
                    </CardContent>
                </Card>

                <Card>
                    <CardHeader className="flex flex-row items-center justify-between pb-2">
                        <CardTitle className="text-sm font-medium text-muted-foreground">
                            Overall Funnel Conversion
                        </CardTitle>
                        <Percent className="h-4 w-4 text-primary" />
                    </CardHeader>
                    <CardContent>
                        <div className="text-2xl font-bold">{funnel?.overall_conversion_rate ?? 0}%</div>
                        <p className="text-xs text-muted-foreground">Landing → First Vote</p>
                    </CardContent>
                </Card>
            </div>

            <Card>
                <CardHeader>
                    <CardTitle className="text-lg">Step-by-Step Funnel Progression</CardTitle>
                    <CardDescription>
                        Progression of unique visitors through each stage of the registration workflow.
                    </CardDescription>
                </CardHeader>
                <CardContent className="space-y-6">
                    <div className="space-y-4">
                        {steps.map((step, idx) => {
                            const isFirst = idx === 0;
                            return (
                                <div key={step.step} className="space-y-2">
                                    <div className="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
                                        <div className="flex items-center gap-2">
                                            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-muted text-xs font-semibold">
                                                {idx + 1}
                                            </span>
                                            <span className="font-medium text-sm">{step.label}</span>
                                        </div>
                                        <div className="flex flex-wrap items-center gap-3 text-xs sm:text-sm">
                                            <span className="font-semibold">
                                                {step.visitor_count.toLocaleString()} visitors
                                            </span>
                                            {!isFirst && (
                                                <>
                                                    <Badge
                                                        variant="solid"
                                                        tone={step.step_conversion_rate >= 70 ? "success" : "neutral"}
                                                        className="font-medium"
                                                    >
                                                        {step.step_conversion_rate}% step conversion
                                                    </Badge>
                                                    <span className="text-muted-foreground">
                                                        ({step.drop_off_count} dropped / {step.drop_off_rate}%)
                                                    </span>
                                                </>
                                            )}
                                        </div>
                                    </div>
                                    <Progress value={step.conversion_rate_from_start} className="h-3 rounded-full" />
                                </div>
                            );
                        })}
                    </div>
                </CardContent>
            </Card>

            <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
                <Card>
                    <CardHeader className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between pb-4">
                        <div>
                            <CardTitle className="text-lg">Top Friction Points</CardTitle>
                            <CardDescription>Ranked drop-off bottlenecks between consecutive steps.</CardDescription>
                        </div>
                        <div className="flex items-center gap-1 rounded-md border p-1 shrink-0">
                            <Button
                                variant={rankBy === "count" ? "default" : "ghost"}
                                size="sm"
                                onClick={() => setRankBy("count")}
                                className="min-h-[44px] px-3 text-xs"
                            >
                                Lost Users
                            </Button>
                            <Button
                                variant={rankBy === "rate" ? "default" : "ghost"}
                                size="sm"
                                onClick={() => setRankBy("rate")}
                                className="min-h-[44px] px-3 text-xs"
                            >
                                Drop-off %
                            </Button>
                        </div>
                    </CardHeader>
                    <CardContent className="space-y-3">
                        {sortedFrictionPoints.length === 0 ? (
                            <p className="text-sm text-muted-foreground">No drop-off events recorded in this period.</p>
                        ) : (
                            sortedFrictionPoints.map((point, index) => {
                                const rank = index + 1;
                                const isHighFriction = point.drop_off_rate >= 30;
                                const isMedFriction = point.drop_off_rate >= 15 && point.drop_off_rate < 30;

                                return (
                                    <div
                                        key={point.label}
                                        className="flex flex-wrap items-center justify-between gap-2 rounded-lg border p-3 text-sm transition-colors hover:bg-muted/40"
                                    >
                                        <div className="flex items-center gap-3">
                                            <span
                                                className={cn(
                                                    "flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-xs font-bold",
                                                    rank === 1
                                                        ? "bg-destructive text-destructive-foreground"
                                                        : "bg-muted text-muted-foreground",
                                                )}
                                            >
                                                #{rank}
                                            </span>
                                            <div>
                                                <div className="font-medium">{point.label}</div>
                                                <div className="text-xs text-muted-foreground">
                                                    {point.drop_off_count.toLocaleString()} users dropped
                                                </div>
                                            </div>
                                        </div>

                                        <div className="flex items-center gap-2">
                                            <Badge
                                                variant="solid"
                                                tone={isHighFriction ? "danger" : isMedFriction ? "warning" : "neutral"}
                                                className="font-semibold text-xs"
                                            >
                                                {point.drop_off_count} users ({point.drop_off_rate}%)
                                            </Badge>
                                        </div>
                                    </div>
                                );
                            })
                        )}
                    </CardContent>
                </Card>

                <Card>
                    <CardHeader>
                        <div className="flex items-center justify-between">
                            <CardTitle className="text-lg">Async Geocoding Latency</CardTitle>
                            <Clock className="h-4 w-4 text-muted-foreground" />
                        </div>
                        <CardDescription>
                            Time spent in pending / processing before legislative assignment completes.
                        </CardDescription>
                    </CardHeader>
                    <CardContent className="space-y-4">
                        <div className="grid grid-cols-2 gap-3 sm:gap-4">
                            <div className="rounded-lg border bg-card p-3">
                                <div className="text-xs font-medium text-muted-foreground">Median (p50) Latency</div>
                                <div className="text-2xl font-bold">{funnel?.latency?.median_seconds ?? 0}s</div>
                                <div className="text-xs text-muted-foreground">Typical waiting duration</div>
                            </div>
                            <div className="rounded-lg border bg-card p-3">
                                <div className="text-xs font-medium text-muted-foreground">95th Percentile (p95)</div>
                                <div className="text-2xl font-bold">{funnel?.latency?.p95_seconds ?? 0}s</div>
                                <div className="text-xs text-muted-foreground">Tail latency threshold</div>
                            </div>
                            <div className="rounded-lg border bg-card p-3">
                                <div className="text-xs font-medium text-muted-foreground">Average Latency</div>
                                <div className="text-xl font-bold">{funnel?.latency?.avg_seconds ?? 0}s</div>
                                <div className="text-xs text-muted-foreground">
                                    Range: {funnel?.latency?.min_seconds ?? 0}s – {funnel?.latency?.max_seconds ?? 0}s
                                </div>
                            </div>
                            <div className="rounded-lg border bg-card p-3">
                                <div className="text-xs font-medium text-muted-foreground">Completed Samples</div>
                                <div className="text-xl font-bold">{funnel?.latency?.sample_count ?? 0}</div>
                                <div className="text-xs text-muted-foreground">Measured background jobs</div>
                            </div>
                        </div>

                        <div className="rounded-lg border p-3 text-xs text-muted-foreground">
                            {!funnel?.latency || funnel.latency.sample_count === 0 ? (
                                <span>No completed geocoding operations recorded in this time range.</span>
                            ) : funnel.latency.median_seconds <= 5.0 ? (
                                <span className="flex items-center gap-1 text-emerald-600 font-medium">
                                    <CheckCircle2 className="h-3.5 w-3.5" /> Geocoding performance is healthy (&lt;5s
                                    median).
                                </span>
                            ) : (
                                <span className="flex items-center gap-1 text-amber-600 font-medium">
                                    <AlertCircle className="h-3.5 w-3.5" /> Elevated geocoding latency detected.
                                </span>
                            )}
                        </div>
                    </CardContent>
                </Card>
            </div>

            <Card>
                <CardHeader>
                    <div className="flex items-center justify-between">
                        <div>
                            <CardTitle className="text-lg">Referral Source Attribution</CardTitle>
                            <CardDescription>
                                Traffic and conversion breakdown by invite links (/s/:key) and organic direct entries.
                            </CardDescription>
                        </div>
                        <Share2 className="h-4 w-4 text-muted-foreground" />
                    </div>
                </CardHeader>
                <CardContent>
                    <div className="overflow-x-auto w-full">
                        <Table>
                            <TableHeader>
                                <TableRow>
                                    <TableHead>Referral Source</TableHead>
                                    <TableHead className="text-right">Visitors</TableHead>
                                    <TableHead className="text-right">Registrations</TableHead>
                                    <TableHead className="text-right">First Votes</TableHead>
                                    <TableHead className="text-right">Conversion %</TableHead>
                                    <TableHead className="text-right">Vote Rate %</TableHead>
                                    <TableHead className="text-right">Action</TableHead>
                                </TableRow>
                            </TableHeader>
                            <TableBody>
                                {!funnel?.attributions || funnel.attributions.length === 0 ? (
                                    <TableRow>
                                        <TableCell colSpan={7} className="py-6 text-center text-muted-foreground">
                                            No attribution events recorded in this time range.
                                        </TableCell>
                                    </TableRow>
                                ) : (
                                    funnel.attributions.map((attr) => (
                                        <TableRow key={attr.source}>
                                            <TableCell className="font-mono text-xs font-semibold sm:text-sm">
                                                {attr.source}
                                            </TableCell>
                                            <TableCell className="text-right font-medium">
                                                {attr.visitors_count.toLocaleString()}
                                            </TableCell>
                                            <TableCell className="text-right font-medium">
                                                {attr.registrations_count.toLocaleString()}
                                            </TableCell>
                                            <TableCell className="text-right font-medium">
                                                {attr.votes_count.toLocaleString()}
                                            </TableCell>
                                            <TableCell className="text-right">
                                                <Badge variant="outline" tone="neutral" className="font-semibold">
                                                    {attr.conversion_rate}%
                                                </Badge>
                                            </TableCell>
                                            <TableCell className="text-right">
                                                <Badge variant="solid" tone="neutral" className="font-semibold">
                                                    {attr.vote_rate}%
                                                </Badge>
                                            </TableCell>
                                            <TableCell className="text-right">
                                                <Button
                                                    variant="ghost"
                                                    size="sm"
                                                    onClick={() => handleAttributionFilter(attr.source)}
                                                    className="min-h-[44px] text-xs font-medium"
                                                >
                                                    Inspect
                                                </Button>
                                            </TableCell>
                                        </TableRow>
                                    ))
                                )}
                            </TableBody>
                        </Table>
                    </div>
                </CardContent>
            </Card>
        </div>
    );
};

export default RegistrationFunnelIndex;
