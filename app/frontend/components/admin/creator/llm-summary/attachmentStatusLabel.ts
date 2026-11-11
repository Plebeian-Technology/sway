import type { ITestimonyAttachment } from "app/frontend/components/admin/creator/llm-summary/types";

// @lat: [[attachment-status-label-mapping#Mirroring the Rails status enums by hand]]
export type TAttachmentDownloadStatus = "pending" | "failed" | "succeeded" | "not_attempted" | "skipped_time_budget";

export type TAttachmentExtractionStatus =
    | "pending"
    | "succeeded"
    | "extraction_failed"
    | "reused_prior_run"
    | "skipped_download_failed"
    | "skipped_time_budget"
    | "not_attempted"
    | "content_denied";

const DOWNLOAD_LABEL: Record<TAttachmentDownloadStatus, string> = {
    pending: "download not finished",
    failed: "download failed",
    succeeded: "downloaded",
    not_attempted: "not attempted — nothing was tried",
    skipped_time_budget: "not downloaded — time budget exhausted",
};

const EXTRACTION_LABEL: Record<TAttachmentExtractionStatus, string> = {
    pending: "not extracted yet",
    succeeded: "extracted",
    // @lat: [[attachment-status-label-mapping#extraction_failed covers three causes with one phrase]]
    extraction_failed: "could not extract text",
    reused_prior_run: "using text captured by an earlier run",
    skipped_download_failed: "not extracted — download failed",
    skipped_time_budget: "not extracted — time budget exhausted",
    not_attempted: "not attempted — nothing was tried",
    content_denied: "read and judged not testimony",
};

// @lat: [[attachment-status-label-mapping#TAttachmentDisposition: what feeds the prompt, and why not if it doesn't]]
export type TAttachmentDisposition = "extracted" | "truncated" | "reused" | "no_text" | "denied";

// @lat: [[attachment-status-label-mapping#attachmentDisposition: why extraction stays "succeeded" on truncation]]
export const attachmentDisposition = (attachment: ITestimonyAttachment): TAttachmentDisposition => {
    if (attachment.extraction_status === "reused_prior_run") return "reused";
    if (attachment.extraction_status === "content_denied") return "denied";
    if (attachment.extraction_status === "succeeded" && attachment.download_status === "succeeded") {
        return attachment.error ? "truncated" : "extracted";
    }
    return "no_text";
};

const phraseFor = <K extends string>(labels: Record<K, string>, status: string): string =>
    (labels as Record<string, string | undefined>)[status] ?? status;

// @lat: [[attachment-status-label-mapping#EXTRACTION_OUTRANKS_DOWNLOAD]]
const EXTRACTION_OUTRANKS_DOWNLOAD: readonly string[] = ["reused_prior_run", "content_denied"];

// @lat: [[attachment-status-label-mapping#Why the download problem wins when both statuses have something to say]]
export const attachmentStatusLabel = (attachment: ITestimonyAttachment): string =>
    attachment.download_status === "succeeded" || EXTRACTION_OUTRANKS_DOWNLOAD.includes(attachment.extraction_status)
        ? phraseFor(EXTRACTION_LABEL, attachment.extraction_status)
        : phraseFor(DOWNLOAD_LABEL, attachment.download_status);
