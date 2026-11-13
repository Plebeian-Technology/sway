import { Link } from "@inertiajs/react";

import ShareBillButton from "app/frontend/components/bill/ShareBillButton";
import type { IFeedBill, TFeedSupport } from "app/frontend/components/feed/types";
import { ROUTES } from "app/frontend/sway_constants";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

interface IProps {
    bill: IFeedBill;
    userSupport: TFeedSupport | null;
}

const renderUserVoteStatus = (userSupport: TFeedSupport) => {
    if (userSupport === "FOR") {
        return (
            <span className="mr-auto text-sm text-muted-foreground">
                {PARITY_COPY.feed.voteLabels.youVotedPrefix}
                <span className="font-semibold text-vote-for">{PARITY_COPY.feed.voteLabels.for}</span>
            </span>
        );
    }
    if (userSupport === "AGAINST") {
        return (
            <span className="mr-auto text-sm text-muted-foreground">
                {PARITY_COPY.feed.voteLabels.youVotedPrefix}
                <span className="font-semibold text-vote-against">{PARITY_COPY.feed.voteLabels.against}</span>
            </span>
        );
    }
    return <span className="mr-auto text-sm text-muted-foreground">{PARITY_COPY.feed.voteLabels.youAbstained}</span>;
};

const FeedBillActions: React.FC<IProps> = ({ bill, userSupport }) => (
    <div className="mt-4 flex flex-wrap items-center gap-2.5">
        {userSupport === null ? (
            <Link
                href={ROUTES.bill(bill.id)}
                className="inline-flex min-h-11 items-center justify-center rounded-md bg-primary px-4.5 text-sm font-semibold text-primary-foreground transition-colors hover:bg-primary/90"
            >
                {PARITY_COPY.feed.voteLabels.goVote}
            </Link>
        ) : (
            renderUserVoteStatus(userSupport)
        )}
        <ShareBillButton bill={bill} className="min-h-11" />
    </div>
);

export default FeedBillActions;
