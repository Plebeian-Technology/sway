import { AlertTriangle, Check, CheckCircle2, Minus, X } from "lucide-react";

import { LegislatorAvatar } from "app/frontend/components/feed/FeedAvatar";
import { FeedBillActions, FeedBillBlock } from "app/frontend/components/feed/FeedBillBlock";
import FeedItemShell from "app/frontend/components/feed/FeedItemShell";
import type { IFeedItem, TFeedSupport } from "app/frontend/components/feed/types";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

interface IProps {
    item: IFeedItem;
}

const VoteValue: React.FC<{ support: TFeedSupport }> = ({ support }) => {
    if (support === "FOR") {
        return (
            <span className="mt-0.5 inline-flex items-center gap-1 text-base font-bold text-vote-for">
                <Check className="size-4" aria-hidden="true" />
                {PARITY_COPY.feed.voteLabels.for}
            </span>
        );
    }
    if (support === "AGAINST") {
        return (
            <span className="mt-0.5 inline-flex items-center gap-1 text-base font-bold text-vote-against">
                <X className="size-4" aria-hidden="true" />
                {PARITY_COPY.feed.voteLabels.against}
            </span>
        );
    }
    return (
        <span className="mt-0.5 inline-flex items-center gap-1 text-base font-bold text-muted-foreground">
            <Minus className="size-4" aria-hidden="true" />
            {PARITY_COPY.feed.voteLabels.abstain}
        </span>
    );
};

const InlineSupportWord: React.FC<{ support: TFeedSupport }> = ({ support }) => {
    if (support === "FOR") {
        return <span className="font-semibold text-vote-for">{PARITY_COPY.feed.voteLabels.for}</span>;
    }
    if (support === "AGAINST") {
        return <span className="font-semibold text-vote-against">{PARITY_COPY.feed.voteLabels.against}</span>;
    }
    return <span className="font-semibold text-muted-foreground">{PARITY_COPY.feed.voteLabels.abstain}</span>;
};

const LegislatorVotedItem: React.FC<IProps> = ({ item }) => {
    const legislator = item.legislator;
    const localeName = item.sway_locale?.name ?? "";

    if (!legislator) {
        return null;
    }

    const subtitle = [legislator.title, legislator.district_name, localeName].filter(Boolean).join(", ");

    const renderWhoLine = () => {
        if (item.user_support) {
            return (
                <>
                    <strong className="font-semibold">{legislator.full_name}</strong>{" "}
                    {PARITY_COPY.feed.legislatorVotedWithUser}
                </>
            );
        }

        if (item.legislator_support === "ABSTAIN") {
            return (
                <>
                    <strong className="font-semibold">{legislator.full_name}</strong>{" "}
                    {PARITY_COPY.feed.legislatorAbstainedOnLocaleBill(localeName)}
                </>
            );
        }

        if (item.legislator_support === "FOR" || item.legislator_support === "AGAINST") {
            return (
                <>
                    <strong className="font-semibold">{legislator.full_name}</strong> voted{" "}
                    <InlineSupportWord support={item.legislator_support} /> a {localeName} bill
                </>
            );
        }

        return <strong className="font-semibold">{legislator.full_name}</strong>;
    };

    return (
        <FeedItemShell
            item={item}
            avatar={<LegislatorAvatar legislator={legislator} />}
            whoLine={renderWhoLine()}
            subtitle={subtitle || undefined}
        >
            {item.bill && <FeedBillBlock bill={item.bill} />}

            {item.user_support && item.legislator_support && (
                <div className="mt-3.5 grid grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)] items-center overflow-hidden rounded-md border border-border">
                    <div className="bg-background px-4 py-3.5">
                        <div className="text-xs text-muted-foreground">{PARITY_COPY.feed.voteLabels.you}</div>
                        <VoteValue support={item.user_support} />
                    </div>

                    {item.agreement === "agree" && (
                        <div className="flex items-center gap-1.5 self-stretch border-x border-border bg-success/12 px-3 text-xs font-semibold text-success">
                            <CheckCircle2 className="size-3.5 shrink-0" aria-hidden="true" />
                            <span>{PARITY_COPY.feed.voteLabels.agree}</span>
                        </div>
                    )}
                    {item.agreement === "differ" && (
                        <div className="flex items-center gap-1.5 self-stretch border-x border-border bg-warning/12 px-3 text-xs font-semibold text-warning">
                            <AlertTriangle className="size-3.5 shrink-0" aria-hidden="true" />
                            <span>{PARITY_COPY.feed.voteLabels.differ}</span>
                        </div>
                    )}
                    {item.agreement === null && <div className="self-stretch border-l border-border" />}

                    <div className="bg-background px-4 py-3.5 text-right">
                        <div className="truncate text-xs text-muted-foreground">{legislator.full_name}</div>
                        <VoteValue support={item.legislator_support} />
                    </div>
                </div>
            )}

            {item.bill && <FeedBillActions bill={item.bill} userSupport={item.user_support} />}
        </FeedItemShell>
    );
};

export default LegislatorVotedItem;
