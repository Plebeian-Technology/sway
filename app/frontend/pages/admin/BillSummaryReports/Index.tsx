import { Link, router, usePoll } from "@inertiajs/react";
import { Filter, Flag, RotateCcw, Search, Wrench } from "lucide-react";
import React, { useState } from "react";

import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import {
    Dialog,
    DialogClose,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from "app/frontend/components/ui/dialog";
import { Input } from "app/frontend/components/ui/input";
import { Label } from "app/frontend/components/ui/label";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "app/frontend/components/ui/table";
import { Textarea } from "app/frontend/components/ui/textarea";
import { ROUTES } from "app/frontend/sway_constants";
import { cn } from "@/lib/utils";

export interface IBillSummaryReport {
    id: number;
    bill_id: number;
    user_id: number | null;
    reason: string;
    details: string | null;
    status: "pending" | "reviewed" | "resolved" | "dismissed";
    summary_snapshot: string | null;
    summary_ai_unreviewed: boolean;
    resolved_at: string | null;
    admin_notes: string | null;
    created_at: string;
    updated_at: string;
    reporter_display: string;
    reason_label: string;
    bill_title: string;
    bill_external_id: string;
    bill_current_summary: string | null;
    bill_link: string | null;
    sway_locale_id: number;
    sway_locale_name: string | null;
    resolved_by_name: string | null;
}

export interface IStatusCounts {
    all: number;
    pending: number;
    reviewed: number;
    resolved: number;
    dismissed: number;
}

export interface ILocaleOption {
    id: number;
    name: string;
}

interface IProps {
    reports: IBillSummaryReport[];
    filter_status: string;
    filter_locale_id?: number | string | null;
    locales: ILocaleOption[];
    status_counts: IStatusCounts;
}

const STATUS_TABS: { key: string; label: string }[] = [
    { key: "pending", label: "Pending" },
    { key: "reviewed", label: "Reviewed" },
    { key: "resolved", label: "Resolved" },
    { key: "dismissed", label: "Dismissed" },
    { key: "all", label: "All" },
];

const BillSummaryReportsIndex: React.FC<IProps> = ({
    reports,
    filter_status,
    filter_locale_id,
    locales,
    status_counts,
}) => {
    usePoll(15000, { only: ["reports", "status_counts"] });

    const [searchQuery, setSearchQuery] = useState("");
    const [actionReport, setActionReport] = useState<IBillSummaryReport | null>(null);
    const [actionType, setActionType] = useState<"resolve" | "dismiss" | null>(null);
    const [adminNotes, setAdminNotes] = useState("");
    const [isSubmitting, setIsSubmitting] = useState(false);

    const handleTabChange = (status: string) => {
        router.get(
            ROUTES.admin_bill_summary_reports,
            { status, locale_id: filter_locale_id || undefined },
            { preserveState: true, preserveScroll: true },
        );
    };

    const handleLocaleChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
        const locale_id = e.target.value;
        router.get(
            ROUTES.admin_bill_summary_reports,
            { status: filter_status, locale_id: locale_id || undefined },
            { preserveState: true, preserveScroll: true },
        );
    };

    const handleQuickReview = (report: IBillSummaryReport) => {
        router.patch(
            `/admin/bill_summary_reports/${report.id}`,
            { bill_summary_report: { status: "reviewed" } },
            { preserveScroll: true },
        );
    };

    const handleReopen = (report: IBillSummaryReport) => {
        router.patch(
            `/admin/bill_summary_reports/${report.id}`,
            { bill_summary_report: { status: "pending" } },
            { preserveScroll: true },
        );
    };

    const handleOpenAction = (report: IBillSummaryReport, type: "resolve" | "dismiss") => {
        setActionReport(report);
        setActionType(type);
        setAdminNotes(report.admin_notes || "");
    };

    const handleCloseAction = () => {
        setActionReport(null);
        setActionType(null);
        setAdminNotes("");
        setIsSubmitting(false);
    };

    const handleConfirmAction = (e: React.FormEvent<HTMLFormElement>) => {
        e.preventDefault();
        if (!actionReport || !actionType) return;

        setIsSubmitting(true);
        router.patch(
            `/admin/bill_summary_reports/${actionReport.id}`,
            {
                bill_summary_report: {
                    status: actionType === "resolve" ? "resolved" : "dismissed",
                    admin_notes: adminNotes,
                },
            },
            {
                preserveScroll: true,
                onSuccess: () => {
                    handleCloseAction();
                },
                onFinish: () => {
                    setIsSubmitting(false);
                },
            },
        );
    };

    const filteredReports = reports.filter((r) => {
        if (!searchQuery.trim()) return true;
        const q = searchQuery.toLowerCase();
        return (
            r.bill_title.toLowerCase().includes(q) ||
            r.bill_external_id.toLowerCase().includes(q) ||
            (r.details && r.details.toLowerCase().includes(q)) ||
            r.reason_label.toLowerCase().includes(q) ||
            r.reporter_display.toLowerCase().includes(q)
        );
    });

    const getStatusBadge = (status: IBillSummaryReport["status"]) => {
        switch (status) {
            case "pending":
                return (
                    <Badge variant="solid" tone="warning">
                        Pending
                    </Badge>
                );
            case "reviewed":
                return (
                    <Badge variant="solid" tone="info">
                        Reviewed
                    </Badge>
                );
            case "resolved":
                return (
                    <Badge variant="solid" tone="success">
                        Resolved
                    </Badge>
                );
            case "dismissed":
                return (
                    <Badge variant="solid" tone="neutral">
                        Dismissed
                    </Badge>
                );
        }
    };

    return (
        <div className="mx-auto w-full max-w-6xl space-y-6 px-4 py-6 sm:px-6">
            <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
                <div>
                    <h1 className="text-2xl font-black tracking-tight text-foreground sm:text-3xl">
                        Bill Summary Reports
                    </h1>
                    <p className="text-sm text-muted-foreground">
                        Review, triage, and resolve reader-submitted reports of inaccurate AI bill summaries.
                    </p>
                </div>
                <Button variant="outline" asChild className="min-h-11 shrink-0 self-start sm:self-auto">
                    <Link href={ROUTES.admin}>← Back to Admin</Link>
                </Button>
            </div>

            <div className="flex flex-col gap-4 rounded-xl border border-border bg-card p-4 shadow-sm">
                <div className="flex flex-wrap gap-2" data-testid="status-filter-tabs">
                    {STATUS_TABS.map((tab) => {
                        const count =
                            tab.key === "all"
                                ? status_counts.all
                                : (status_counts[tab.key as keyof IStatusCounts] ?? 0);
                        const isActive = filter_status === tab.key;
                        return (
                            <Button
                                key={tab.key}
                                type="button"
                                variant={isActive ? "default" : "outline"}
                                size="sm"
                                onClick={() => handleTabChange(tab.key)}
                                className={cn("min-h-11 cursor-pointer gap-2 font-bold", isActive && "shadow-neo-sm")}
                                data-testid={`tab-status-${tab.key}`}
                            >
                                <span>{tab.label}</span>
                                <span
                                    className={cn(
                                        "rounded-full px-1.5 py-0.2 text-[11px] font-black",
                                        isActive
                                            ? "bg-primary-foreground text-primary"
                                            : "bg-muted text-muted-foreground",
                                    )}
                                >
                                    {count}
                                </span>
                            </Button>
                        );
                    })}
                </div>

                <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                    <div className="flex items-center gap-2">
                        <Filter className="size-4 shrink-0 text-muted-foreground" aria-hidden="true" />
                        <select
                            value={filter_locale_id?.toString() || ""}
                            onChange={handleLocaleChange}
                            aria-label="Filter by jurisdiction"
                            className="min-h-11 w-full rounded-md border border-input bg-background px-3 py-2 text-sm shadow-sm focus:outline-none focus:ring-2 focus:ring-primary"
                            data-testid="select-locale-filter"
                        >
                            <option value="">All Locales</option>
                            {locales.map((loc) => (
                                <option key={loc.id} value={loc.id.toString()}>
                                    {loc.name}
                                </option>
                            ))}
                        </select>
                    </div>

                    <div className="relative flex items-center sm:col-span-1 lg:col-span-2">
                        <Search className="absolute left-3 size-4 text-muted-foreground" aria-hidden="true" />
                        <Input
                            type="search"
                            placeholder="Filter by bill, keyword, reporter, or reason…"
                            value={searchQuery}
                            onChange={(e) => setSearchQuery(e.target.value)}
                            className="min-h-11 pl-9 text-sm"
                            data-testid="input-search-reports"
                        />
                    </div>
                </div>
            </div>

            {filteredReports.length === 0 ? (
                <Card>
                    <CardContent className="flex flex-col items-center justify-center py-12 text-center text-muted-foreground">
                        <Flag className="mb-3 size-10 text-muted-foreground/50" aria-hidden="true" />
                        <p className="text-base font-semibold">No reports match the current filters.</p>
                        <p className="text-xs">Select a different tab or clear the search query.</p>
                    </CardContent>
                </Card>
            ) : (
                <>
                    <div className="hidden rounded-xl border border-border bg-card shadow-sm md:block">
                        <div data-slot="table-container" className="relative w-full overflow-x-auto">
                            <Table>
                                <TableHeader>
                                    <TableRow>
                                        <TableHead className="w-16">ID</TableHead>
                                        <TableHead className="min-w-[200px]">Bill</TableHead>
                                        <TableHead className="w-40">Reason</TableHead>
                                        <TableHead className="min-w-[240px]">Reader Feedback</TableHead>
                                        <TableHead className="w-32">Reporter</TableHead>
                                        <TableHead className="w-28">Status</TableHead>
                                        <TableHead className="text-right">Actions</TableHead>
                                    </TableRow>
                                </TableHeader>
                                <TableBody>
                                    {filteredReports.map((report) => (
                                        <TableRow key={report.id} data-testid={`report-row-${report.id}`}>
                                            <TableCell className="font-mono text-xs font-bold text-muted-foreground">
                                                #{report.id}
                                            </TableCell>
                                            <TableCell>
                                                <div className="space-y-0.5">
                                                    <Link
                                                        href={ROUTES.bill(report.bill_id)}
                                                        className="font-bold text-foreground hover:underline"
                                                    >
                                                        {report.bill_external_id}: {report.bill_title}
                                                    </Link>
                                                    {report.sway_locale_name && (
                                                        <div className="text-xs text-muted-foreground">
                                                            {report.sway_locale_name}
                                                        </div>
                                                    )}
                                                </div>
                                            </TableCell>
                                            <TableCell>
                                                <Badge variant="outline" className="text-xs">
                                                    {report.reason_label}
                                                </Badge>
                                            </TableCell>
                                            <TableCell>
                                                <p className="line-clamp-3 text-xs text-foreground">
                                                    {report.details || (
                                                        <span className="italic text-muted-foreground">
                                                            No details provided
                                                        </span>
                                                    )}
                                                </p>
                                                {report.admin_notes && (
                                                    <p className="mt-1 text-[11px] font-semibold text-primary">
                                                        Admin note: {report.admin_notes}
                                                    </p>
                                                )}
                                            </TableCell>
                                            <TableCell className="text-xs text-muted-foreground">
                                                {report.reporter_display}
                                            </TableCell>
                                            <TableCell>{getStatusBadge(report.status)}</TableCell>
                                            <TableCell className="text-right">
                                                <div className="flex items-center justify-end gap-1.5">
                                                    <Button
                                                        variant="ghost"
                                                        size="sm"
                                                        asChild
                                                        className="h-8 gap-1 text-xs"
                                                        title="Edit Summary in Bill Creator"
                                                        data-testid={`btn-bill-creator-${report.id}`}
                                                    >
                                                        <Link href={ROUTES.billCreatorTab(report.bill_id, "summary")}>
                                                            <Wrench className="size-3.5" aria-hidden="true" />
                                                            <span>Creator</span>
                                                        </Link>
                                                    </Button>

                                                    {report.status === "pending" && (
                                                        <Button
                                                            variant="outline"
                                                            size="sm"
                                                            onClick={() => handleQuickReview(report)}
                                                            className="h-8 text-xs font-semibold text-info hover:bg-info/10"
                                                            data-testid={`btn-review-${report.id}`}
                                                        >
                                                            Review
                                                        </Button>
                                                    )}

                                                    {report.status !== "resolved" && (
                                                        <Button
                                                            variant="outline"
                                                            size="sm"
                                                            onClick={() => handleOpenAction(report, "resolve")}
                                                            className="h-8 text-xs font-semibold text-success hover:bg-success/10"
                                                            data-testid={`btn-resolve-${report.id}`}
                                                        >
                                                            Resolve
                                                        </Button>
                                                    )}

                                                    {report.status !== "dismissed" && (
                                                        <Button
                                                            variant="outline"
                                                            size="sm"
                                                            onClick={() => handleOpenAction(report, "dismiss")}
                                                            className="h-8 text-xs font-semibold text-muted-foreground hover:bg-muted"
                                                            data-testid={`btn-dismiss-${report.id}`}
                                                        >
                                                            Dismiss
                                                        </Button>
                                                    )}

                                                    {(report.status === "resolved" ||
                                                        report.status === "dismissed") && (
                                                        <Button
                                                            variant="ghost"
                                                            size="sm"
                                                            onClick={() => handleReopen(report)}
                                                            className="h-8 text-xs"
                                                            title="Reopen Report"
                                                        >
                                                            <RotateCcw className="size-3.5" aria-hidden="true" />
                                                        </Button>
                                                    )}
                                                </div>
                                            </TableCell>
                                        </TableRow>
                                    ))}
                                </TableBody>
                            </Table>
                        </div>
                    </div>

                    <div className="space-y-4 md:hidden" data-testid="mobile-report-cards">
                        {filteredReports.map((report) => (
                            <Card key={report.id} className="overflow-hidden" data-testid={`report-card-${report.id}`}>
                                <CardHeader className="p-4 pb-2">
                                    <div className="flex items-center justify-between gap-2">
                                        <span className="font-mono text-xs font-bold text-muted-foreground">
                                            Report #{report.id}
                                        </span>
                                        {getStatusBadge(report.status)}
                                    </div>
                                    <CardTitle className="text-base font-black text-foreground">
                                        <Link href={ROUTES.bill(report.bill_id)} className="hover:underline">
                                            {report.bill_external_id}: {report.bill_title}
                                        </Link>
                                    </CardTitle>
                                    <CardDescription className="flex flex-wrap items-center gap-2 text-xs">
                                        {report.sway_locale_name && <span>{report.sway_locale_name}</span>}
                                        <span>•</span>
                                        <span>{report.reporter_display}</span>
                                    </CardDescription>
                                </CardHeader>

                                <CardContent className="space-y-3 p-4 pt-1">
                                    <div className="flex items-center gap-2">
                                        <Badge variant="outline" className="text-xs">
                                            {report.reason_label}
                                        </Badge>
                                    </div>

                                    <div className="rounded-lg border border-border bg-surface-2 p-3 text-xs text-foreground">
                                        <p className="font-semibold text-muted-foreground">Reader's comment:</p>
                                        <p className="mt-1">
                                            {report.details || (
                                                <span className="italic text-muted-foreground">
                                                    No details provided
                                                </span>
                                            )}
                                        </p>
                                    </div>

                                    {report.admin_notes && (
                                        <div className="rounded-lg bg-primary/5 p-2.5 text-xs text-primary">
                                            <span className="font-bold">Admin note: </span>
                                            {report.admin_notes}
                                        </div>
                                    )}
                                </CardContent>

                                <CardFooter className="flex flex-col gap-2 p-4 pt-0">
                                    <Button
                                        asChild
                                        variant="outline"
                                        className="min-h-11 w-full gap-2 font-bold"
                                        data-testid={`mobile-btn-creator-${report.id}`}
                                    >
                                        <Link href={ROUTES.billCreatorTab(report.bill_id, "summary")}>
                                            <Wrench className="size-4" aria-hidden="true" />
                                            Edit in Bill Creator
                                        </Link>
                                    </Button>

                                    <div className="grid w-full grid-cols-2 gap-2">
                                        {report.status === "pending" && (
                                            <Button
                                                variant="outline"
                                                onClick={() => handleQuickReview(report)}
                                                className="min-h-11 text-xs font-bold text-info"
                                                data-testid={`mobile-btn-review-${report.id}`}
                                            >
                                                Mark Reviewed
                                            </Button>
                                        )}

                                        {report.status !== "resolved" && (
                                            <Button
                                                variant="outline"
                                                onClick={() => handleOpenAction(report, "resolve")}
                                                className="min-h-11 text-xs font-bold text-success"
                                                data-testid={`mobile-btn-resolve-${report.id}`}
                                            >
                                                Resolve
                                            </Button>
                                        )}

                                        {report.status !== "dismissed" && (
                                            <Button
                                                variant="outline"
                                                onClick={() => handleOpenAction(report, "dismiss")}
                                                className="min-h-11 text-xs font-bold text-muted-foreground"
                                                data-testid={`mobile-btn-dismiss-${report.id}`}
                                            >
                                                Dismiss
                                            </Button>
                                        )}

                                        {(report.status === "resolved" || report.status === "dismissed") && (
                                            <Button
                                                variant="outline"
                                                onClick={() => handleReopen(report)}
                                                className="min-h-11 text-xs font-bold"
                                            >
                                                Reopen
                                            </Button>
                                        )}
                                    </div>
                                </CardFooter>
                            </Card>
                        ))}
                    </div>
                </>
            )}

            <Dialog open={Boolean(actionReport && actionType)} onOpenChange={(open) => !open && handleCloseAction()}>
                <DialogContent className="max-w-lg">
                    {actionReport && actionType && (
                        <form onSubmit={handleConfirmAction} className="space-y-4">
                            <DialogHeader>
                                <DialogTitle className="text-lg font-black text-foreground">
                                    {actionType === "resolve" ? "Mark Report as Resolved" : "Dismiss Report"}
                                </DialogTitle>
                                <DialogDescription className="text-xs text-muted-foreground">
                                    {actionType === "resolve"
                                        ? `Confirm resolution for report #${actionReport.id} on ${actionReport.bill_external_id}.`
                                        : `Dismiss report #${actionReport.id} on ${actionReport.bill_external_id}.`}
                                </DialogDescription>
                            </DialogHeader>

                            <div className="space-y-2">
                                <Label
                                    htmlFor="action-admin-notes"
                                    className="text-xs font-bold uppercase tracking-wider text-muted-foreground"
                                >
                                    Admin Notes (Optional)
                                </Label>
                                <Textarea
                                    id="action-admin-notes"
                                    rows={3}
                                    placeholder={
                                        actionType === "resolve"
                                            ? "e.g. Summary regenerated with Claude 3.5 Sonnet in Bill Creator."
                                            : "e.g. Verified against official legislative text; summary is accurate as written."
                                    }
                                    value={adminNotes}
                                    onChange={(e) => setAdminNotes(e.target.value)}
                                    className="text-sm"
                                />
                            </div>

                            <DialogFooter className="gap-2 sm:gap-0">
                                <DialogClose asChild>
                                    <Button
                                        type="button"
                                        variant="outline"
                                        onClick={handleCloseAction}
                                        className="min-h-11"
                                    >
                                        Cancel
                                    </Button>
                                </DialogClose>
                                <Button
                                    type="submit"
                                    disabled={isSubmitting}
                                    className={cn(
                                        "min-h-11 font-bold",
                                        actionType === "resolve"
                                            ? "bg-success text-success-foreground hover:bg-success/90"
                                            : "bg-destructive text-destructive-foreground hover:bg-destructive/90",
                                    )}
                                    data-testid="btn-confirm-action"
                                >
                                    {isSubmitting
                                        ? "Saving…"
                                        : actionType === "resolve"
                                          ? "Confirm Resolution"
                                          : "Confirm Dismissal"}
                                </Button>
                            </DialogFooter>
                        </form>
                    )}
                </DialogContent>
            </Dialog>
        </div>
    );
};

export default BillSummaryReportsIndex;
