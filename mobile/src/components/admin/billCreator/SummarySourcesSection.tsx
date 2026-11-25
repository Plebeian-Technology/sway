// @lat: [[mobile-bill-creator#Sections#The summary sources section]]
import React, { useRef, useState } from "react";
import { Text, View } from "react-native";

import { apiClient } from "../../../api/client";
import { Routes } from "../../../api/routes";
import type { BillCreatorTabProps } from "../../../hooks/admin/useBillCreator";
import { Pressable } from "../../ui/Pressable";

interface SourceRecord {
    source_kind: "diff" | "extracted" | "none";
    source_chars: number;
    source_cap: number;
    source_truncated: boolean;
    extracted_text_chars: number;
    diff_target: string | null;
    diff_sections_modified: number | null;
    diff_sections_referenced: number | null;
    diff_sections_not_found: number | null;
    diff_generated_at: string | null;
    citation_keys_offered: number;
    citation_keys_total: number;
    citation_sample_titles: string[];
    news_search_available: boolean;
    news_fetched_at: string | null;
    newsroom_domains: string[];
    news_articles_offered: number;
    news_articles: { title: string; host: string }[];
}

interface SourceRead extends SourceRecord {
    built_at: string;
    llm_model: string | null;
    llm_provider: string | null;
}

interface Sources {
    read?: SourceRead | null;
    now: SourceRecord;
    summary_generated_at: string | null;
    summary_model: string | null;
    summary_provider: string | null;
}

type DocumentField = "bill_details" | "source_text" | "citations" | "news";

interface SourceDocuments {
    origin: "run" | "now";
    built_at: string | null;
    bill_details: string | null;
    source_text: string | null;
    citations: string | null;
    news: string | null;
}

interface DocumentsResponse {
    summary_source_documents?: SourceDocuments | null;
}

type RowKey = "details" | "text" | "law" | "news";

interface Stamp {
    label: string;
    tone: "warning" | "neutral";
}

interface Row {
    key: RowKey;
    name: string;
    field: DocumentField;
    sentence: string;
    note?: string;
    stamp?: Stamp;
    items?: string[];
    date?: string;
}

type NewerStamp = (input: string | null, stamp: Stamp) => Stamp | undefined;

const OPERATOR_PASTE_PROVIDER = "operator_paste";
const NEWER_THAN_SUMMARY: Stamp = { label: "Newer than summary", tone: "warning" };
const DIFF_RECORD_NEWER: Stamp = { label: "Diff record newer", tone: "warning" };

const ROW_FACTS: Record<RowKey, (keyof SourceRecord)[]> = {
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

const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";
const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";
const bodyText = "text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark";
const stampText = `rounded border border-border-light dark:border-border-dark px-1.5 ${mutedText}`;
const panelClass = "gap-2 rounded-lg border border-border-light dark:border-border-dark p-3";

const countNoun = (count: number, singular: string, plural: string) =>
    `${count.toLocaleString()} ${count === 1 ? singular : plural}`;

const formatDate = (iso: string) =>
    new Date(iso).toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric" });

const isNewerThan = (input: string | null, summary: string | null) =>
    input !== null && summary !== null && new Date(input).getTime() > new Date(summary).getTime();

const hasChanged = (key: RowKey, read: SourceRecord, now: SourceRecord) =>
    ROW_FACTS[key].some((fact) => JSON.stringify(read[fact]) !== JSON.stringify(now[fact]));

const modelName = (model: string | null, provider: string | null) =>
    model ?? provider ?? "a model the run did not record";

const lawTargetName = (target: string | null) => {
    if (target === "charter") return "the City Charter";
    if (target === "code") return "the City Code";
    return "existing law";
};

const newsroomCount = (domains: string[]) => new Set(domains.map((domain) => domain.split("/")[0])).size;

const detailsRow = (): Row => ({
    key: "details",
    name: "Bill details",
    field: "bill_details",
    sentence: "Its number, title, status and release date.",
});

const diffRecordNote = (source: SourceRecord): string | undefined => {
    if (source.diff_sections_modified === null && source.diff_sections_referenced === null) return undefined;

    const generated = source.diff_generated_at ? ` (generated ${formatDate(source.diff_generated_at)})` : "";
    const modified = countNoun(source.diff_sections_modified ?? 0, "amended section", "amended sections");
    const parts = [
        `The stored diff record${generated} lists ${modified} and ${(source.diff_sections_referenced ?? 0).toLocaleString()} referenced against ${lawTargetName(source.diff_target)}.`,
    ];
    if (source.diff_sections_not_found) {
        parts.push(`${countNoun(source.diff_sections_not_found, "section was", "sections were")} named but not found.`);
    }
    parts.push("Those counts describe that record, not the file the model read, which View shows.");
    return parts.join(" ");
};

const textRow = (source: SourceRecord, newerStamp: NewerStamp): Row => {
    if (source.source_kind === "none") {
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
    let stamp: Stamp | undefined;

    if (source.source_kind === "diff") {
        parts.push(`The diff file, ${countNoun(source.source_chars, "character", "characters")}.`);
        if (source.extracted_text_chars > 0) {
            parts.push(
                `The bill's own text (${countNoun(source.extracted_text_chars, "character", "characters")}) is on file, but the diff takes its place.`,
            );
        }
        note = diffRecordNote(source);
        stamp = newerStamp(source.diff_generated_at, DIFF_RECORD_NEWER);
    } else {
        parts.push(
            `The bill's own text, ${countNoun(source.source_chars, "character", "characters")}. No diff file exists for this bill.`,
        );
    }

    if (source.source_truncated) {
        parts.push(`Only the first ${source.source_cap.toLocaleString()} characters reach the model.`);
        stamp = { label: "Truncated", tone: "warning" };
    }

    return { key: "text", name: "Bill text", field: "source_text", sentence: parts.join(" "), note, stamp };
};

const lawRow = (source: SourceRecord): Row => {
    const base = { key: "law" as const, name: "Law code", field: "citations" as const };
    if (source.citation_keys_total === 0) {
        return { ...base, sentence: "No sections of existing law were found in the bill, so it can cite none." };
    }
    if (source.citation_keys_offered === 0) {
        return {
            ...base,
            sentence: `${countNoun(source.citation_keys_total, "section was", "sections were")} found, but none could be offered to cite.`,
        };
    }

    let sentence = `${countNoun(source.citation_keys_offered, "citation key", "citation keys")} the model may cite, repeats counted.`;
    const named = source.citation_sample_titles.join("; ");
    if (named.length > 0) sentence += ` Sampled titles: ${named}${named.endsWith(".") ? "" : "."}`;
    const leftOut = source.citation_keys_total - source.citation_keys_offered;
    if (leftOut > 0) sentence += ` ${countNoun(leftOut, "more key was", "more keys were")} found but left out.`;
    return { ...base, sentence };
};

const newsRow = (source: SourceRecord, newerStamp: NewerStamp): Row => {
    const base = { key: "news" as const, name: "News", field: "news" as const };
    const rooms = newsroomCount(source.newsroom_domains);
    if (rooms === 0) {
        return {
            ...base,
            sentence: "No newsrooms are set up for this jurisdiction, so the model cannot cite reporting.",
        };
    }
    if (!source.news_search_available) {
        return {
            ...base,
            sentence: "Not searched. The local model cannot search the web, so no reporting reaches it.",
            stamp: { label: "Not searched", tone: "neutral" },
        };
    }
    if (source.news_fetched_at === null) {
        return {
            ...base,
            sentence: `Not searched yet. The next run searches ${countNoun(rooms, "newsroom", "newsrooms")} first.`,
        };
    }

    const date = `Searched ${formatDate(source.news_fetched_at)}`;
    const stamp = newerStamp(source.news_fetched_at, NEWER_THAN_SUMMARY);
    if (source.news_articles_offered === 0) {
        return {
            ...base,
            sentence: `Searched ${countNoun(rooms, "newsroom", "newsrooms")} and found nothing about this bill.`,
            date,
            stamp,
        };
    }
    return {
        ...base,
        sentence: `${countNoun(source.news_articles_offered, "article", "articles")} from ${countNoun(rooms, "newsroom", "newsrooms")} searched.`,
        items: source.news_articles.map((article) =>
            article.title ? `${article.host}: ${article.title}` : article.host,
        ),
        date,
        stamp,
    };
};

const unrecordedSentence = (sources: Sources) => {
    if (sources.summary_generated_at === null) return "No summary has been written yet, so no run has read anything.";
    if (sources.summary_provider === OPERATOR_PASTE_PROVIDER) {
        return `This summary was pasted by hand on ${formatDate(sources.summary_generated_at)}, so no model read anything for it.`;
    }
    return `Nothing was recorded for the run that wrote this summary on ${formatDate(sources.summary_generated_at)} with ${modelName(sources.summary_model, sources.summary_provider)}.`;
};

const originSentence = (documents: SourceDocuments | null, loading: boolean) => {
    if (loading) return "Loading the text.";
    if (documents === null) return "The text could not be loaded.";
    if (documents.origin === "now") return "Rebuilt just now from the bill as it stands.";
    return documents.built_at
        ? `The text the run of ${formatDate(documents.built_at)} sent, byte for byte.`
        : "The text the run sent, byte for byte.";
};

const DocumentPanel: React.FC<{
    row: Row;
    documents: SourceDocuments | null;
    loading: boolean;
}> = ({ row, documents, loading }) => {
    const testID = `admin-summary-source-${row.key}-document`;
    const text = documents === null ? null : documents[row.field];
    const sectionName = row.name.toLowerCase();

    return (
        <View testID={testID} className={panelClass}>
            <Text className={labelText}>{row.name}</Text>
            <Text testID={`${testID}-origin`} className={mutedText}>
                {originSentence(documents, loading)}
            </Text>
            {loading ? (
                <Text testID={`${testID}-loading`} className={mutedText}>
                    Loading the text the model was given…
                </Text>
            ) : null}
            {!loading && documents === null ? (
                <Text testID={`${testID}-failed`} className={mutedText}>
                    Could not load the text. Close this and open it again.
                </Text>
            ) : null}
            {!loading && documents?.origin === "now" ? (
                <Text testID={`${testID}-rebuilt`} className={bodyText}>
                    No run was recorded for this bill, so this text was rebuilt just now. It is what a run would send
                    today, not what one sent.
                </Text>
            ) : null}
            {!loading && documents !== null && text === null ? (
                <Text testID={`${testID}-absent`} className={mutedText}>
                    The prompt carried no {sectionName} section at all, so the model read none.
                </Text>
            ) : null}
            {!loading && text !== null && text.trim().length === 0 ? (
                <Text testID={`${testID}-empty`} className={mutedText}>
                    The prompt carried a {sectionName} section with no text in it.
                </Text>
            ) : null}
            {!loading && text !== null && text.trim().length > 0 ? (
                <Text testID={`${testID}-text`} className={`font-mono ${mutedText}`} selectable>
                    {text}
                </Text>
            ) : null}
        </View>
    );
};

const SourceRow: React.FC<{
    row: Row;
    changed: boolean;
    open: boolean;
    documents: SourceDocuments | null;
    loading: boolean;
    onView: () => void;
}> = ({ row, changed, open, documents, loading, onView }) => (
    <View
        testID={`admin-summary-source-${row.key}`}
        className="gap-1 border-t border-border-light dark:border-border-dark py-2"
    >
        <Text className={labelText}>{row.name}</Text>
        <Text className={bodyText}>{row.sentence}</Text>
        <View className="flex-row flex-wrap items-center gap-2">
            {row.stamp ? (
                <Text testID={`admin-summary-source-${row.key}-stamp`} className={stampText}>
                    {row.stamp.label}
                </Text>
            ) : null}
            {changed ? (
                <Text testID={`admin-summary-source-${row.key}-changed`} className={stampText}>
                    Changed since run
                </Text>
            ) : null}
        </View>
        {row.items?.map((item) => (
            <Text key={item} className={bodyText}>
                {`• ${item}`}
            </Text>
        ))}
        {row.note ? (
            <Text testID={`admin-summary-source-${row.key}-note`} className={mutedText}>
                {row.note}
            </Text>
        ) : null}
        {row.date ? <Text className={mutedText}>{row.date}</Text> : null}
        <View className="flex-row">
            <Pressable
                testID={`admin-summary-source-${row.key}-view`}
                variant="outline"
                accessibilityLabel={`View the ${row.name.toLowerCase()} the model was given`}
                accessibilityState={{ expanded: open }}
                onPress={onView}
            >
                <Text className={labelText}>{open ? "Hide" : "View"}</Text>
            </Pressable>
        </View>
        {open ? <DocumentPanel row={row} documents={documents} loading={loading} /> : null}
    </View>
);

const SummarySourcesPanel: React.FC<BillCreatorTabProps & { billId: number }> = ({ billId, data }) => {
    const sources = (data.summary_sources ?? null) as Sources | null;
    const [openRow, setOpenRow] = useState<RowKey | null>(null);
    const [documents, setDocuments] = useState<SourceDocuments | null>(null);
    const [loading, setLoading] = useState(false);
    const latestRequest = useRef(0);

    const viewRow = async (key: RowKey) => {
        if (openRow === key) {
            setOpenRow(null);
            return;
        }
        const request = ++latestRequest.current;
        setOpenRow(key);
        setDocuments(null);
        setLoading(true);
        try {
            const response = await apiClient.get<DocumentsResponse>(
                Routes.adminBillCreatorSummarySourceDocuments(billId),
            );
            if (request === latestRequest.current) setDocuments(response.summary_source_documents ?? null);
        } catch {
            if (request === latestRequest.current) setDocuments(null);
        } finally {
            if (request === latestRequest.current) setLoading(false);
        }
    };

    if (!sources) {
        return (
            <View testID="admin-summary-sources-empty" className="px-4 mt-6">
                <Text className={mutedText}>No record of what the model reads is available for this bill.</Text>
            </View>
        );
    }

    const read = sources.read ?? null;
    const record = read ?? sources.now;
    const newerStamp: NewerStamp = read
        ? () => undefined
        : (input, stamp) => (isNewerThan(input, sources.summary_generated_at) ? stamp : undefined);
    const rows = [detailsRow(), textRow(record, newerStamp), lawRow(record), newsRow(record, newerStamp)];

    return (
        <View testID="admin-summary-sources" className="px-4 mt-6 gap-2">
            <Text className={labelText}>What the model read</Text>
            {read ? (
                <Text testID="admin-summary-sources-provenance" className={mutedText}>
                    {`Read by ${modelName(read.llm_model, read.llm_provider)} on ${formatDate(read.built_at)}.`}
                </Text>
            ) : (
                <View testID="admin-summary-sources-not-recorded" className={panelClass}>
                    <Text className={stampText}>Not recorded</Text>
                    <Text className={bodyText}>{unrecordedSentence(sources)}</Text>
                    <Text className={bodyText}>
                        The rows below are what a run would read today, not a record of what one read.
                    </Text>
                </View>
            )}
            {rows.map((row) => (
                <SourceRow
                    key={row.key}
                    row={row}
                    changed={read !== null && hasChanged(row.key, read, sources.now)}
                    open={openRow === row.key}
                    documents={documents}
                    loading={loading}
                    onView={() => void viewRow(row.key)}
                />
            ))}
            <Text testID="admin-summary-sources-exclusions" className={mutedText}>
                Testimony and organization positions are not sent to the model. The prompt tells it to leave them out,
                and the request carries only the four inputs above.
            </Text>
        </View>
    );
};

const SummarySourcesSection: React.FC<BillCreatorTabProps> = (props) => {
    if (props.billId === null) {
        return (
            <View testID="admin-summary-sources-empty" className="px-4 mt-6">
                <Text className={mutedText}>Save this bill to see what the model read.</Text>
            </View>
        );
    }
    return <SummarySourcesPanel {...props} billId={props.billId} />;
};

export default SummarySourcesSection;
