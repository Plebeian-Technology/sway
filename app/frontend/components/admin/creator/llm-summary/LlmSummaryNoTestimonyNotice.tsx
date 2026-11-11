import { NO_TESTIMONY_NOTICE_ID } from "app/frontend/components/admin/creator/llm-summary/noTestimonyNoticeId";

interface IProps {
    // @lat: [[llm-summary-no-testimony-notice-copy#hasDrafts]]
    hasDrafts: boolean;
    // @lat: [[llm-summary-no-testimony-notice-copy#allDraftsRetracted]]
    allDraftsRetracted: boolean;
}

// @lat: [[llm-summary-no-testimony-notice-copy#NOTHING_GENERATED: names the field, not a direction]]
const NOTHING_GENERATED =
    "No public testimony available for this bill — positions are not generated without testimony. " +
    "Fill in the Supplemental testimony field on this tab and click Save testimony to enable generation.";

// @lat: [[llm-summary-no-testimony-notice-copy#allDraftsRetracted]]
const DRAFTS_RETRACTED =
    "No public testimony available for this bill — the draft positions below were drawn from testimony that has " +
    "been withdrawn, so they cannot be approved. Pasting testimony back does not restore them: regenerate the " +
    "positions once testimony is available, or reject them.";

const DRAFTS_UNAPPROVABLE =
    "No public testimony available for this bill — the draft positions below were drawn from testimony that is no " +
    "longer on file, so they cannot be approved. Paste the testimony back into the Supplemental testimony field on " +
    "this tab and click Save testimony, or reject them.";

// @lat: [[llm-summary-no-testimony-notice-copy#Why the component moved out of the empty-list branch]]
const LlmSummaryNoTestimonyNotice: React.FC<IProps> = ({ hasDrafts, allDraftsRetracted }) => (
    <p
        // @lat: [[llm-summary-no-testimony-notice-copy#The id and aria-describedby]]
        id={NO_TESTIMONY_NOTICE_ID}
        className={
            hasDrafts
                ? "rounded-lg border-neo border-border-strong bg-muted p-3 text-sm text-foreground"
                : "text-sm italic text-muted-foreground"
        }
        data-testid="llm-no-testimony"
    >
        {hasDrafts ? (allDraftsRetracted ? DRAFTS_RETRACTED : DRAFTS_UNAPPROVABLE) : NOTHING_GENERATED}
    </p>
);

export default LlmSummaryNoTestimonyNotice;
