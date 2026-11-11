import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import { formatEta } from "app/frontend/sway_utils";

interface IProps {
    processed: number;
    total: number | null;
    currentBillExternalId: string | null;
    etaSeconds: number | null;
    queued: string[];
}

const PipelineRunningDetail: React.FC<IProps> = ({ processed, total, currentBillExternalId, etaSeconds, queued }) => {
    return (
        <>
            <div className="flex flex-col gap-1 text-sm">
                <div className="flex items-center gap-1.5">
                    <span data-testid="pipeline-current-bill" className="font-semibold tabular-nums lining-nums">
                        {currentBillExternalId ?? "—"}
                    </span>
                    <FeatureInfo note="pipeline.runningDetail" />
                </div>
                {etaSeconds !== null && (
                    <span
                        data-testid="pipeline-eta"
                        className="text-xs uppercase tracking-widest text-muted-foreground tabular-nums lining-nums"
                    >
                        ~{formatEta(etaSeconds)} remaining
                    </span>
                )}
                <span className="text-xs tabular-nums lining-nums text-muted-foreground">
                    {processed} / {total ?? "?"} bills
                </span>
            </div>

            {queued.length > 0 && (
                <details className="text-sm">
                    <summary className="flex min-h-[44px] cursor-pointer items-center font-semibold">
                        Queue (<span className="tabular-nums lining-nums">{queued.length}</span> remaining)
                    </summary>
                    <ul data-testid="pipeline-queued-list" className="mt-2 flex flex-col gap-1 text-xs">
                        {queued.map((id) => (
                            <li key={id} className="tabular-nums lining-nums">
                                {id}
                            </li>
                        ))}
                    </ul>
                </details>
            )}
        </>
    );
};

export default PipelineRunningDetail;
