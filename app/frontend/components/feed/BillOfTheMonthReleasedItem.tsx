import { formatReleaseMonthUtc } from "app/frontend/components/feed/dateGrouping";
import FeedAvatar from "app/frontend/components/feed/FeedAvatar";
import FeedBillActions from "app/frontend/components/feed/FeedBillActions";
import FeedBillBlock from "app/frontend/components/feed/FeedBillBlock";
import FeedItemShell from "app/frontend/components/feed/FeedItemShell";
import type { IFeedItem } from "app/frontend/components/feed/types";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

interface IProps {
    item: IFeedItem;
}

const BillOfTheMonthReleasedItem: React.FC<IProps> = ({ item }) => {
    const localeName = item.sway_locale?.name ?? "";
    const monthName = formatReleaseMonthUtc(item.occurred_at);

    return (
        <FeedItemShell
            item={item}
            avatar={<FeedAvatar kind="locale" localeName={localeName} />}
            whoLine={
                <>
                    <strong className="font-semibold">{localeName}</strong>{" "}
                    {PARITY_COPY.feed.billOfTheMonthReleasedSuffix(monthName)}
                </>
            }
        >
            {item.bill && (
                <>
                    <FeedBillBlock bill={item.bill} showSummary />
                    <FeedBillActions bill={item.bill} userSupport={item.user_support} />
                </>
            )}
        </FeedItemShell>
    );
};

export default BillOfTheMonthReleasedItem;
