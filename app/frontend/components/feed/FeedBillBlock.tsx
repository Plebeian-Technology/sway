import { Link } from "@inertiajs/react";

import AiUnreviewedNotice from "app/frontend/components/bill/AiUnreviewedNotice";
import { shortBillTitle } from "app/frontend/components/bill/sway_utils/billTitle";
import { cleanFeedSummary } from "app/frontend/components/feed/feedSummary";
import type { IFeedBill } from "app/frontend/components/feed/types";
import { ROUTES } from "app/frontend/sway_constants";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

interface IProps {
    bill: IFeedBill;
    showSummary?: boolean;
}

const FeedBillBlock: React.FC<IProps> = ({ bill, showSummary = false }) => {
    const cleanedSummary = showSummary ? cleanFeedSummary(bill.summary) : null;

    return (
        <>
            <Link
                href={ROUTES.bill(bill.id)}
                className="mt-3.5 block rounded-md border border-border bg-card p-4 text-card-foreground transition-colors hover:border-border-strong"
            >
                <div className="text-xs font-medium text-muted-foreground">{bill.external_id}</div>
                <div className="mt-1 text-base font-semibold leading-snug text-foreground">
                    {shortBillTitle(bill.title)}
                </div>
                {cleanedSummary && (
                    <>
                        <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{cleanedSummary}</p>
                        <AiUnreviewedNotice unreviewed={bill.summary_ai_unreviewed} />
                    </>
                )}
            </Link>
            <div className="mt-2 flex items-center gap-3 text-xs text-muted-foreground tabular-nums">
                <span>{PARITY_COPY.feed.viewedCount(bill.view_count)}</span>
                <span>{PARITY_COPY.feed.sharedCount(bill.share_count)}</span>
            </div>
        </>
    );
};

export default FeedBillBlock;
