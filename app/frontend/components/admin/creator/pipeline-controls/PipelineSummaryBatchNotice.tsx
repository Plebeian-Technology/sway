import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import { formatDateTime, relativeTime } from "app/frontend/sway_utils/datetimes";
import type { ISummaryBatchProgress } from "app/frontend/components/admin/creator/pipeline-controls/types";

interface IProps {
    summaryBatch: ISummaryBatchProgress | null | undefined;
}

// @lat: [[llm-summaries#Batch summarisation#What the operator sees while a batch is outstanding]]
const PipelineSummaryBatchNotice: React.FC<IProps> = ({ summaryBatch }) => {
    if (!summaryBatch || !summaryBatch.awaiting) return null;

    const itemsReturned = summaryBatch.items_succeeded + summaryBatch.items_failed;

    return (
        <Alert variant="info" data-testid="pipeline-summary-batch-notice">
            <div className="col-start-2 flex items-center gap-1.5">
                <AlertTitle className="min-w-0">Awaiting summary batch</AlertTitle>
                <FeatureInfo note="pipeline.summaryBatchNotice" className="shrink-0" />
            </div>
            <AlertDescription>
                <p>
                    Nothing is stuck. The summaries went out in chunks, and a chunk reports only once the whole chunk
                    has ended, so this moves one chunk at a time.
                </p>
                <p>
                    Chunks read back: {summaryBatch.batches_ingested} of {summaryBatch.batches_total}.
                </p>
                <p>
                    Items returned: {itemsReturned} of {summaryBatch.items_total} submitted —{" "}
                    {summaryBatch.items_succeeded} succeeded, {summaryBatch.items_failed} failed.
                </p>
                {summaryBatch.first_submitted_at ? (
                    <p>First submitted {relativeTime(summaryBatch.first_submitted_at)}.</p>
                ) : null}
                <p>
                    No completion estimate is available. The only deadline is the hard 24-hour expiry
                    {summaryBatch.expires_at ? `, at ${formatDateTime(summaryBatch.expires_at)}` : ""}.
                </p>
            </AlertDescription>
        </Alert>
    );
};

export default PipelineSummaryBatchNotice;
