import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";
import {
    attachmentDisposition,
    attachmentStatusLabel,
} from "app/frontend/components/admin/creator/llm-summary/attachmentStatusLabel";
import type { ITestimonyAttachment } from "app/frontend/components/admin/creator/llm-summary/types";
import { attachmentCount, plural } from "app/frontend/components/admin/creator/llm-summary/attachmentCountText";

interface IProps {
    attachments: ITestimonyAttachment[] | null;
}

// @lat: [[admin-mirror-display-vs-identity#attachment_id: the identity, kept separate from the label]]
const AttachmentRows: React.FC<{ attachments: ITestimonyAttachment[] }> = ({ attachments }) => (
    <ul className="list-disc pl-4">
        {attachments.map((a, i) => (
            <li key={a.attachment_id || `${a.filename}-${i}`} className="font-mono text-xs">
                {a.filename || "(unnamed attachment)"} — {attachmentStatusLabel(a)}
                {a.error ? `: ${a.error}` : ""}
            </li>
        ))}
    </ul>
);

// @lat: [[testimony-attachment-warning-lists#Why AttachmentAlert is one shared shell]]
const AttachmentAlert: React.FC<{
    variant: "warning" | "info";
    testId: string;
    title: string;
    attachments: ITestimonyAttachment[];
    children: React.ReactNode;
}> = ({ variant, testId, title, attachments, children }) => (
    <Alert variant={variant} data-testid={testId}>
        <AlertTitle>{title}</AlertTitle>
        <AlertDescription>
            <AttachmentRows attachments={attachments} />
            <p className="pt-1 text-sm">{children}</p>
        </AlertDescription>
    </Alert>
);

// @lat: [[testimony-attachment-warning-lists#attachmentCountText.ts centralizes the plural/count wording]]
const LlmSummaryTestimonyAttachmentWarning: React.FC<IProps> = ({ attachments }) => {
    const all = attachments ?? [];
    const missing = all.filter((a) => attachmentDisposition(a) === "no_text");
    const reused = all.filter((a) => attachmentDisposition(a) === "reused");
    const truncated = all.filter((a) => attachmentDisposition(a) === "truncated");
    const denied = all.filter((a) => attachmentDisposition(a) === "denied");
    if (missing.length === 0 && reused.length === 0 && truncated.length === 0 && denied.length === 0) return null;

    return (
        <>
            {missing.length > 0 && (
                <AttachmentAlert
                    variant="warning"
                    testId="llm-testimony-attachment-warning"
                    title={plural(missing.length, "Testimony attachment issue")}
                    attachments={missing}
                >
                    Paste the testimony text into Supplemental testimony below and click Save testimony if needed.
                </AttachmentAlert>
            )}
            {truncated.length > 0 && (
                <AttachmentAlert
                    variant="warning"
                    testId="llm-testimony-attachment-truncated"
                    title={`Testimony text was truncated${attachmentCount(truncated.length)}`}
                    attachments={truncated}
                >
                    The start of each document is in the testimony feeding the summary and the org-position call; the
                    rest was cut at the per-attachment size cap. Paste the part a position turns on into Supplemental
                    testimony and click Save testimony if it fell outside.
                </AttachmentAlert>
            )}
            {reused.length > 0 && (
                <AttachmentAlert
                    variant="info"
                    testId="llm-testimony-attachment-reused"
                    title={`Testimony text carried over from an earlier run${attachmentCount(reused.length)}`}
                    attachments={reused}
                >
                    This text is already part of the testimony feeding the summary and the org-position call — it does
                    not need to be supplied again.
                </AttachmentAlert>
            )}
            {denied.length > 0 && (
                <AttachmentAlert
                    variant="info"
                    testId="llm-testimony-attachment-denied"
                    title={`${plural(denied.length, "Document")} read and judged not testimony${attachmentCount(denied.length)}`}
                    attachments={denied}
                >
                    The classifier read each document and decided it is not public testimony, so its text is left out of
                    the testimony feeding the summary and the org-position call. If a verdict is wrong, paste that
                    document&apos;s text into Supplemental testimony below and click Save testimony.
                </AttachmentAlert>
            )}
        </>
    );
};

export default LlmSummaryTestimonyAttachmentWarning;
