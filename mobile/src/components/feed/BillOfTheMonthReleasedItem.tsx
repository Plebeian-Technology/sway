import React from "react";
import { Text } from "react-native";

import { PARITY_COPY } from "../../../../app/frontend/sway_constants/parityCopy";
import { formatReleaseMonthUtc } from "./dateGrouping";
import FeedAvatar from "./FeedAvatar";
import FeedBillActions from "./FeedBillActions";
import FeedBillBlock from "./FeedBillBlock";
import FeedItemShell from "./FeedItemShell";
import type { IFeedBill, IFeedItem } from "./types";

interface IProps {
    item: IFeedItem;
    onPressBill: (billId: number) => void;
    onShareBill: (bill: IFeedBill) => void;
}

const BillOfTheMonthReleasedItem: React.FC<IProps> = ({ item, onPressBill, onShareBill }) => {
    const localeName = item.sway_locale?.name ?? "";
    const monthName = formatReleaseMonthUtc(item.occurred_at);

    return (
        <FeedItemShell
            item={item}
            subject="locale"
            avatar={<FeedAvatar kind="locale" localeName={localeName} />}
            whoLine={
                <>
                    <Text style={{ fontFamily: "OpenSans-SemiBold" }}>{localeName}</Text>{" "}
                    {PARITY_COPY.feed.billOfTheMonthReleasedSuffix(monthName)}
                </>
            }
        >
            {item.bill ? (
                <>
                    <FeedBillBlock bill={item.bill} showSummary onPressBill={onPressBill} />
                    <FeedBillActions
                        bill={item.bill}
                        userSupport={item.user_support}
                        onPressBill={onPressBill}
                        onShareBill={onShareBill}
                    />
                </>
            ) : null}
        </FeedItemShell>
    );
};

export default BillOfTheMonthReleasedItem;
