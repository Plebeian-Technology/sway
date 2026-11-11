import { router } from "@inertiajs/react";
import { useMemo, useState } from "react";
import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import { useConfirm } from "app/frontend/components/ui/confirm-dialog";
import { Input } from "app/frontend/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "app/frontend/components/ui/table";
import CollapsiblePanel from "app/frontend/components/CollapsiblePanel";
import Pagination from "app/frontend/components/Pagination";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import { notifyServerRefusal } from "app/frontend/components/admin/creator/notifyServerRefusal";
import { usePagination } from "app/frontend/hooks/usePagination";
import { countNoun } from "app/frontend/sway_utils/countNoun";

export interface ISendingServiceDomainRow {
    id: number;
    domain: string;
    label: string;
    sender_count: number;
    machine_sent_letter_count: number;
    letter_count: number;
    bill_count: number;
}

interface IProps {
    billId: number;
    domains: ISendingServiceDomainRow[];
    // @lat: [[bill-creator-pipeline-llm-tab#SendingServicesPanel design and untrusted-domain guards]]
    total?: number;
}

const CONFIRMED_LABEL = "confirmed";
const PROPOSED_LABEL = "proposed";
const PAGE_SIZE = 5;

// @lat: [[bill-creator-pipeline-llm-tab#SendingServicesPanel design and untrusted-domain guards]]
const STAMPS: Record<string, { text: string; tone: "success" | "info" | "neutral" }> = {
    [CONFIRMED_LABEL]: { text: "CONFIRMED", tone: "success" },
    [PROPOSED_LABEL]: { text: "PROPOSED", tone: "info" },
};
const UNLABELED_STAMP = { text: "UNLABELED", tone: "neutral" } as const;

const stampFor = (label: string) => STAMPS[label] ?? UNLABELED_STAMP;

// @lat: [[bill-creator-pipeline-llm-tab#SendingServicesPanel design and untrusted-domain guards]]
const machineSentShare = (row: ISendingServiceDomainRow): number =>
    row.letter_count === 0 ? 0 : row.machine_sent_letter_count / row.letter_count;

// @lat: [[bill-creator-pipeline-llm-tab#SendingServicesPanel design and untrusted-domain guards]]
const shareSubline = (row: ISendingServiceDomainRow): string =>
    `${row.machine_sent_letter_count.toLocaleString()} of ${countNoun(row.letter_count, "letter", "letters")}`;

// @lat: [[bill-creator-pipeline-llm-tab#SendingServicesPanel design and untrusted-domain guards]]
const SendingServicesPanel: React.FC<IProps> = ({ billId, domains, total }) => {
    const confirm = useConfirm();
    const [submittingId, setSubmittingId] = useState<number | null>(null);
    const [query, setQuery] = useState("");

    // @lat: [[pagination#Search filters the capped list, not the full table]]
    const filteredDomains = useMemo(() => {
        const needle = query.trim().toLowerCase();
        return needle ? domains.filter((row) => row.domain.toLowerCase().includes(needle)) : domains;
    }, [domains, query]);

    const { page, pageCount, pageItems, goToPage } = usePagination(filteredDomains, PAGE_SIZE);

    const applyLabel = (row: ISendingServiceDomainRow, label: string) => {
        setSubmittingId(row.id);
        router.patch(
            `/sending_service_domains/${row.id}`,
            { label, bill_id: billId },
            {
                preserveScroll: true,
                // @lat: [[bill-creator-pipeline-llm-tab#SendingServicesPanel design and untrusted-domain guards]]
                onError: (errors) => notifyServerRefusal(errors, "sending_service", "Label change failed."),
                onFinish: () => setSubmittingId(null),
            },
        );
    };

    const handleConfirm = async (row: ISendingServiceDomainRow) => {
        const confirmed = await confirm({
            title: `Confirm ${row.domain} as a sending service?`,
            description:
                "Every future letter from this domain will be marked machine-sent. This does not say what those letters argue.",
            confirmLabel: "Confirm",
            cancelLabel: "Cancel",
        });
        if (!confirmed) return;
        applyLabel(row, CONFIRMED_LABEL);
    };

    const handleRemove = async (row: ISendingServiceDomainRow) => {
        const confirmed = await confirm({
            title: `Remove the sending-service label from ${row.domain}?`,
            description: "Future letters from this domain will be read as one person's letter.",
            confirmLabel: "Remove the label",
            cancelLabel: "Cancel",
        });
        if (!confirmed) return;
        applyLabel(row, "none");
    };

    return (
        <CollapsiblePanel storageKey="sway:pipeline-llm:accordion:sending-services" title="Sending services">
            <div className="flex flex-col gap-3" data-testid="sending-services-panel">
                {/* @lat: [[bill-creator-pipeline-llm-tab#SendingServicesPanel design and untrusted-domain guards]] */}
                <p className="text-sm text-muted-foreground">
                    A sending service says only that a letter was machine-sent. It never says which campaign a letter
                    belongs to, or what it argues.
                </p>

                {total !== undefined && total > domains.length ? (
                    <p className="text-sm text-muted-foreground tabular-nums">
                        Showing the {domains.length.toLocaleString()} domains with the most machine-sent letters, of{" "}
                        {total.toLocaleString()}.
                    </p>
                ) : null}

                {domains.length === 0 ? (
                    <p className="text-sm italic text-muted-foreground">No sending-service domains yet.</p>
                ) : (
                    <>
                        <Input
                            type="search"
                            placeholder="Search by domain"
                            aria-label="Search by domain"
                            value={query}
                            onChange={(event) => setQuery(event.target.value)}
                            className="h-8 max-w-xs text-sm"
                            data-testid="sending-services-search"
                        />
                        {filteredDomains.length === 0 ? (
                            // @lat: [[pagination#A search that cannot reach every row says so]]
                            <p className="text-sm italic text-muted-foreground">
                                No domains match this search
                                {total !== undefined && total > domains.length
                                    ? ` among the ${domains.length.toLocaleString()} shown — ${(
                                          total - domains.length
                                      ).toLocaleString()} more are not loaded.`
                                    : "."}
                            </p>
                        ) : (
                            <>
                                <Table>
                                    <TableHeader>
                                        <TableRow>
                                            <TableHead scope="col">Domain</TableHead>
                                            <TableHead scope="col">Senders</TableHead>
                                            <TableHead scope="col">Bills</TableHead>
                                            <TableHead scope="col">Machine-sent share</TableHead>
                                            <TableHead scope="col">Label</TableHead>
                                            <TableHead scope="col" aria-label="Actions">
                                                <span className="sr-only">Actions</span>
                                                <FeatureInfo note="pipeline.sendingServiceDecision" />
                                            </TableHead>
                                        </TableRow>
                                    </TableHeader>
                                    <TableBody>
                                        {pageItems.map((row) => {
                                            const confirmed = row.label === CONFIRMED_LABEL;
                                            const submitting = submittingId === row.id;
                                            const stamp = stampFor(row.label);
                                            return (
                                                // @lat: [[bill-creator-pipeline-llm-tab#SendingServicesPanel design and untrusted-domain guards]]
                                                <TableRow key={row.id} data-testid={`sending-service-row-${row.id}`}>
                                                    {/* @lat: [[bill-creator-pipeline-llm-tab#SendingServicesPanel design and untrusted-domain guards]] */}
                                                    <TableCell className="whitespace-normal break-all">
                                                        {row.domain}
                                                    </TableCell>
                                                    <TableCell className="tabular-nums lining-nums">
                                                        {row.sender_count.toLocaleString()}
                                                    </TableCell>
                                                    <TableCell className="tabular-nums lining-nums">
                                                        {row.bill_count.toLocaleString()}
                                                    </TableCell>
                                                    <TableCell className="tabular-nums lining-nums">
                                                        <div className="flex flex-col gap-1">
                                                            <span>{Math.round(machineSentShare(row) * 100)}%</span>
                                                            <span className="text-xs text-muted-foreground">
                                                                {shareSubline(row)}
                                                            </span>
                                                        </div>
                                                    </TableCell>
                                                    <TableCell>
                                                        <Badge
                                                            variant="stamp"
                                                            tone={stamp.tone}
                                                            data-testid={`sending-service-stamp-${row.id}`}
                                                        >
                                                            {stamp.text}
                                                        </Badge>
                                                    </TableCell>
                                                    <TableCell>
                                                        <div className="flex flex-wrap gap-2">
                                                            {confirmed ? (
                                                                <Button
                                                                    type="button"
                                                                    size="sm"
                                                                    variant="outline"
                                                                    disabled={submitting}
                                                                    onClick={() => handleRemove(row)}
                                                                    data-testid={`btn-remove-sending-service-${row.id}`}
                                                                >
                                                                    Remove this label
                                                                </Button>
                                                            ) : (
                                                                <>
                                                                    <Button
                                                                        type="button"
                                                                        size="sm"
                                                                        variant="default"
                                                                        disabled={submitting}
                                                                        onClick={() => handleConfirm(row)}
                                                                        data-testid={`btn-confirm-sending-service-${row.id}`}
                                                                    >
                                                                        Confirm as a sending service
                                                                    </Button>
                                                                    <Button
                                                                        type="button"
                                                                        size="sm"
                                                                        variant="outline"
                                                                        disabled={submitting}
                                                                        onClick={() => handleRemove(row)}
                                                                        data-testid={`btn-not-sending-service-${row.id}`}
                                                                    >
                                                                        Not a sending service
                                                                    </Button>
                                                                </>
                                                            )}
                                                        </div>
                                                    </TableCell>
                                                </TableRow>
                                            );
                                        })}
                                    </TableBody>
                                </Table>
                                <Pagination
                                    page={page}
                                    pageCount={pageCount}
                                    onPageChange={goToPage}
                                    className="justify-center pt-3"
                                />
                            </>
                        )}
                    </>
                )}
            </div>
        </CollapsiblePanel>
    );
};

export default SendingServicesPanel;
