import { Link } from "@inertiajs/react";

import ShareBillButton from "app/frontend/components/bill/ShareBillButton";
import type { IFeedBill, TFeedSupport } from "app/frontend/components/feed/types";
import { ROUTES } from "app/frontend/sway_constants";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

interface IBillBlockProps {
    bill: IFeedBill;
    showSummary?: boolean;
}

export const FeedBillBlock: React.FC<IBillBlockProps> = ({ bill, showSummary = false }) => (
    <>
        <Link
            href={ROUTES.bill(bill.id)}
            className="mt-3.5 block rounded-md border border-border bg-card p-4 text-card-foreground transition-colors hover:border-border-strong"
        >
            <div className="text-xs font-medium text-muted-foreground">{bill.external_id}</div>
            <div className="mt-1 text-base font-semibold leading-snug text-foreground">{bill.title}</div>
            {showSummary && bill.summary && (
                <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{bill.summary}</p>
            )}
        </Link>
        <div className="mt-2 flex items-center gap-3 text-xs text-muted-foreground tabular-nums">
            <span>{PARITY_COPY.feed.votedCount(bill.vote_count)}</span>
            <span>{PARITY_COPY.feed.sharedCount(bill.share_count)}</span>
        </div>
    </>
);

const UserVoteStatus: React.FC<{ userSupport: TFeedSupport }> = ({ userSupport }) => {
    if (userSupport === "FOR") {
        return (
            <span className="mr-auto text-sm text-muted-foreground">
                You voted <span className="font-semibold text-vote-for">{PARITY_COPY.feed.voteLabels.for}</span>
            </span>
        );
    }
    if (userSupport === "AGAINST") {
        return (
            <span className="mr-auto text-sm text-muted-foreground">
                You voted <span className="font-semibold text-vote-against">{PARITY_COPY.feed.voteLabels.against}</span>
            </span>
        );
    }
    return <span className="mr-auto text-sm text-muted-foreground">{PARITY_COPY.feed.voteLabels.youAbstained}</span>;
};

interface IActionsProps {
    bill: IFeedBill;
    userSupport: TFeedSupport | null;
}

export const FeedBillActions: React.FC<IActionsProps> = ({ bill, userSupport }) => (
    <div className="mt-4 flex flex-wrap items-center gap-2.5">
        {userSupport === null ? (
            <Link
                href={ROUTES.bill(bill.id)}
                className="inline-flex min-h-11 items-center justify-center rounded-md bg-primary px-4.5 text-sm font-semibold text-primary-foreground transition-colors hover:bg-primary/90"
            >
                {PARITY_COPY.feed.voteLabels.goVote}
            </Link>
        ) : (
            <UserVoteStatus userSupport={userSupport} />
        )}
        <ShareBillButton bill={bill} className="min-h-11" />
    </div>
);
