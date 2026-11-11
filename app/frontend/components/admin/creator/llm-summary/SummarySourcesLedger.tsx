import { usePage } from "@inertiajs/react";
import { useCallback, useState } from "react";
import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import { isOperatorPasted } from "app/frontend/components/admin/creator/llm-summary/provenance";
import SummarySourceDocumentDialog, {
    TSummaryDocumentField,
} from "app/frontend/components/admin/creator/llm-summary/SummarySourceDocumentDialog";
import { ISummarySourceRecord, ISummarySources } from "app/frontend/components/admin/creator/llm-summary/types";
import { useSummarySourceDocuments } from "app/frontend/components/admin/creator/llm-summary/useSummarySourceDocuments";
import { countNoun } from "app/frontend/sway_utils/countNoun";
import { formatDate } from "app/frontend/sway_utils/datetimes";

interface IPageProps {
    summary_sources?: ISummarySources | null;
    [key: string]: unknown;
}

interface IStamp {
    label: string;
    tone: "warning" | "neutral";
}

type TRowKey = "details" | "text" | "law" | "news";

interface IRow {
    key: TRowKey;
    name: string;
    field: TSummaryDocumentField;
    sentence: string;
    // @lat: [[bill-creator-summary-tab#Why the diff counts are attributed to a record]]
    note?: string;
    stamp?: IStamp;
    items?: string[];
    date?: string;
}

type TNewerStamp = (input: string | null, stamp: IStamp) => IStamp | undefined;

const NEWER_THAN_SUMMARY: IStamp = { label: "Newer than summary", tone: "warning" };

const DIFF_RECORD_NEWER: IStamp = { label: "Diff record newer", tone: "warning" };

const CHANGED_SINCE_RUN: IStamp = { label: "Changed since run", tone: "warning" };

// @lat: [[bill-creator-summary-tab#Why the panel lists what the model reads]]
const ROW_FACTS: Record<TRowKey, Array<keyof ISummarySourceRecord>> = {
    details: [],
    text: [
        "source_kind",
        "source_chars",
        "source_cap",
        "source_truncated",
        "extracted_text_chars",
        "diff_target",
        "diff_sections_modified",
        "diff_sections_referenced",
        "diff_generated_at",
    ],
    law: ["citation_keys_offered", "citation_keys_total", "citation_sample_titles"],
    news: ["news_search_available", "news_fetched_at", "newsroom_domains", "news_articles_offered", "news_articles"],
};

const isNewerThan = (input: string | null, summary: string | null): boolean =>
    input !== null && summary !== null && new Date(input).getTime() > new Date(summary).getTime();

const hasChanged = (key: TRowKey, read: ISummarySourceRecord, now: ISummarySourceRecord): boolean =>
    ROW_FACTS[key].some((fact) => JSON.stringify(read[fact]) !== JSON.stringify(now[fact]));

const modelName = (model: string | null, provider: string | null): string =>
    model ?? provider ?? "a model the run did not record";

const lawTargetName = (target: string | null): string => {
    if (target === "charter") return "the City Charter";
    if (target === "code") return "the City Code";
    return "existing law";
};

// @lat: [[bill-creator-summary-tab#Why the panel lists what the model reads]]
const newsroomCount = (domains: string[] = []): number => new Set((domains || []).map((d) => d.split("/")[0])).size;

const detailsRow = (): IRow => ({
    key: "details",
    name: "Bill details",
    field: "bill_details",
    sentence: "Its number, title, status and release date.",
});

// @lat: [[bill-creator-summary-tab#Why the diff counts are attributed to a record]]
const diffRecordNote = (s: ISummarySourceRecord): string | undefined => {
    if (s.diff_sections_modified === null && s.diff_sections_referenced === null) return undefined;

    const generated = s.diff_generated_at ? ` (generated ${formatDate(s.diff_generated_at)})` : "";
    const modified = countNoun(s.diff_sections_modified ?? 0, "amended section", "amended sections");
    const parts = [
        `The stored diff record${generated} lists ${modified} and ${(s.diff_sections_referenced ?? 0).toLocaleString()} referenced against ${lawTargetName(s.diff_target)}.`,
    ];
    if (s.diff_sections_not_found) {
        parts.push(`${countNoun(s.diff_sections_not_found, "section was", "sections were")} named but not found.`);
    }
    parts.push("Those counts describe that record, not the file the model read, which View shows.");

    return parts.join(" ");
};

const textRow = (s: ISummarySourceRecord, newerStamp: TNewerStamp): IRow => {
    if (s.source_kind === "none") {
        return {
            key: "text",
            name: "Bill text",
            field: "source_text",
            sentence: "Nothing. No bill text has been fetched, so the model is told to find it itself.",
            stamp: { label: "No text", tone: "warning" },
        };
    }

    const parts: string[] = [];
    let note: string | undefined;
    let stamp: IStamp | undefined;

    if (s.source_kind === "diff") {
        parts.push(`The diff file, ${countNoun(s.source_chars, "character", "characters")}.`);
        if (s.extracted_text_chars > 0) {
            parts.push(
                `The bill's own text (${countNoun(s.extracted_text_chars, "character", "characters")}) is on file, but the diff takes its place.`,
            );
        }
        note = diffRecordNote(s);
        stamp = newerStamp(s.diff_generated_at, DIFF_RECORD_NEWER);
    } else {
        parts.push(
            `The bill's own text, ${countNoun(s.source_chars, "character", "characters")}. No diff file exists for this bill.`,
        );
    }

    if (s.source_truncated) {
        parts.push(`Only the first ${s.source_cap.toLocaleString()} characters reach the model.`);
        stamp = { label: "Truncated", tone: "warning" };
    }

    return { key: "text", name: "Bill text", field: "source_text", sentence: parts.join(" "), note, stamp };
};

const lawRow = (s: ISummarySourceRecord): IRow => {
    if (s.citation_keys_total === 0) {
        return {
            key: "law",
            name: "Law code",
            field: "citations",
            sentence: "No sections of existing law were found in the bill, so it can cite none.",
        };
    }
    if (s.citation_keys_offered === 0) {
        return {
            key: "law",
            name: "Law code",
            field: "citations",
            sentence: `${countNoun(s.citation_keys_total, "section was", "sections were")} found, but none could be offered to cite.`,
        };
    }

    // @lat: [[bill-creator-summary-tab#Why the panel lists what the model reads]]
    let sentence = `${countNoun(s.citation_keys_offered, "citation key", "citation keys")} the model may cite, repeats counted.`;
    const named = (s.citation_sample_titles || []).join("; ");
    if (named.length > 0) sentence += ` Sampled titles: ${named}${named.endsWith(".") ? "" : "."}`;
    const leftOut = s.citation_keys_total - s.citation_keys_offered;
    if (leftOut > 0) sentence += ` ${countNoun(leftOut, "more key was", "more keys were")} found but left out.`;

    return { key: "law", name: "Law code", field: "citations", sentence };
};

const newsRow = (s: ISummarySourceRecord, newerStamp: TNewerStamp): IRow => {
    const rooms = newsroomCount(s.newsroom_domains);
    if (rooms === 0) {
        return {
            key: "news",
            name: "News",
            field: "news",
            sentence: "No newsrooms are set up for this jurisdiction, so the model cannot cite reporting.",
        };
    }
    if (!s.news_search_available) {
        return {
            key: "news",
            name: "News",
            field: "news",
            sentence: "Not searched. The local model cannot search the web, so no reporting reaches it.",
            stamp: { label: "Not searched", tone: "neutral" },
        };
    }
    if (s.news_fetched_at === null) {
        return {
            key: "news",
            name: "News",
            field: "news",
            sentence: `Not searched yet. The next run searches ${countNoun(rooms, "newsroom", "newsrooms")} first.`,
        };
    }

    const date = `Searched ${formatDate(s.news_fetched_at)}`;
    const stamp = newerStamp(s.news_fetched_at, NEWER_THAN_SUMMARY);
    if (s.news_articles_offered === 0) {
        return {
            key: "news",
            name: "News",
            field: "news",
            sentence: `Searched ${countNoun(rooms, "newsroom", "newsrooms")} and found nothing about this bill.`,
            date,
            stamp,
        };
    }
    return {
        key: "news",
        name: "News",
        field: "news",
        sentence: `${countNoun(s.news_articles_offered, "article", "articles")} from ${countNoun(rooms, "newsroom", "newsrooms")} searched.`,
        items: (s.news_articles || []).map((a) => (a.title ? `${a.host}: ${a.title}` : a.host)),
        date,
        stamp,
    };
};

const unrecordedSentence = (s: ISummarySources): string => {
    if (s.summary_generated_at === null) return "No summary has been written yet, so no run has read anything.";
    if (isOperatorPasted(s.summary_provider)) {
        return `This summary was pasted by hand on ${formatDate(s.summary_generated_at)}, so no model read anything for it.`;
    }
    return `Nothing was recorded for the run that wrote this summary on ${formatDate(s.summary_generated_at)} with ${modelName(s.summary_model, s.summary_provider)}.`;
};

// @lat: [[bill-creator-summary-tab#Why the panel lists what the model reads]]
const SummarySourcesLedger: React.FC = () => {
    const sources = usePage<IPageProps>().props.summary_sources;
    const { documents, loading, load } = useSummarySourceDocuments();
    const [openRow, setOpenRow] = useState<TRowKey | null>(null);

    const openDocument = useCallback(
        (key: TRowKey) => {
            setOpenRow(key);
            load();
        },
        [load],
    );

    if (!sources) return null;

    const read = sources.read ?? null;
    const record = read ?? sources.now;
    const newerStamp: TNewerStamp = read
        ? () => undefined
        : (input, stamp) => (isNewerThan(input, sources.summary_generated_at) ? stamp : undefined);

    const rows: IRow[] = [detailsRow(), textRow(record, newerStamp), lawRow(record), newsRow(record, newerStamp)];

    return (
        <section className="flex flex-col gap-2" data-testid="summary-sources-ledger">
            <div className="flex min-w-0 items-center gap-1.5">
                <h4 className="text-base font-medium">What the model read</h4>
                <FeatureInfo note="summary.sources" />
            </div>
            {read ? (
                <p
                    className="text-sm text-muted-foreground tabular-nums lining-nums"
                    data-testid="summary-sources-provenance"
                >
                    Read by {modelName(read.llm_model, read.llm_provider)} on {formatDate(read.built_at)}.
                </p>
            ) : (
                <div
                    className="flex flex-col gap-1 rounded-lg bg-warning/12 p-2 ring-1 ring-warning ring-inset"
                    data-testid="summary-sources-not-recorded"
                >
                    <div className="flex flex-wrap items-center gap-2">
                        <Badge variant="stamp" tone="warning">
                            Not recorded
                        </Badge>
                        <span className="text-sm tabular-nums lining-nums">{unrecordedSentence(sources)}</span>
                    </div>
                    <span className="text-sm text-foreground">
                        The rows below are what a run would read today, not a record of what one read.
                    </span>
                </div>
            )}
            <dl className="flex flex-col">
                {rows.map((row) => (
                    <div
                        key={row.key}
                        className="grid gap-x-4 gap-y-1 border-t border-border py-2.5 sm:grid-cols-[7rem_1fr]"
                        data-testid={`summary-source-${row.key}`}
                    >
                        <dt className="text-sm font-semibold">{row.name}</dt>
                        <dd className="flex min-w-0 flex-col gap-1 text-sm text-muted-foreground">
                            <div className="flex flex-wrap items-center gap-2">
                                <span className="max-w-prose tabular-nums lining-nums">{row.sentence}</span>
                                {row.stamp && (
                                    <Badge
                                        variant="stamp"
                                        tone={row.stamp.tone}
                                        data-testid={`summary-source-${row.key}-stamp`}
                                    >
                                        {row.stamp.label}
                                    </Badge>
                                )}
                                {read && hasChanged(row.key, read, sources.now) && (
                                    <Badge
                                        variant="stamp"
                                        tone={CHANGED_SINCE_RUN.tone}
                                        data-testid={`summary-source-${row.key}-changed`}
                                    >
                                        {CHANGED_SINCE_RUN.label}
                                    </Badge>
                                )}
                                <Button
                                    type="button"
                                    variant="outline"
                                    size="xs"
                                    onClick={() => openDocument(row.key)}
                                    aria-label={`View the ${row.name.toLowerCase()} the model was given`}
                                    data-testid={`summary-source-${row.key}-view`}
                                    className="min-h-[44px] sm:min-h-6 sm:h-6"
                                >
                                    View
                                </Button>
                            </div>
                            {row.items && (
                                <ul className="flex flex-col gap-0.5 pl-4 [list-style:disc]">
                                    {row.items.map((item) => (
                                        <li key={item} className="max-w-prose">
                                            {item}
                                        </li>
                                    ))}
                                </ul>
                            )}
                            {row.note && (
                                <span
                                    className="max-w-prose text-xs tabular-nums lining-nums"
                                    data-testid={`summary-source-${row.key}-note`}
                                >
                                    {row.note}
                                </span>
                            )}
                            {row.date && <span className="text-xs tabular-nums lining-nums">{row.date}</span>}
                        </dd>
                    </div>
                ))}
            </dl>
            <p className="text-xs text-muted-foreground" data-testid="summary-sources-exclusions">
                Testimony and organization positions are not sent to the model. The prompt tells it to leave them out,
                and the request carries only the four inputs above.
            </p>
            {rows.map((row) => (
                <SummarySourceDocumentDialog
                    key={row.key}
                    rowKey={row.key}
                    name={row.name}
                    field={row.field}
                    open={openRow === row.key}
                    onOpenChange={(open) => setOpenRow(open ? row.key : null)}
                    documents={documents}
                    loading={loading}
                />
            ))}
        </section>
    );
};

export default SummarySourcesLedger;
