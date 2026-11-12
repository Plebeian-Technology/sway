import React from "react";
import { Text } from "react-native";

import { PARITY_COPY } from "../../../../app/frontend/sway_constants/parityCopy";
import { formatReleaseMonthUtc } from "./dateGrouping";
import { LocaleTile } from "./FeedAvatar";
import { FeedBillActions, FeedBillBlock } from "./FeedBillBlock";
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
    const tail = PARITY_COPY.feed.billOfTheMonthReleased(localeName, monthName).slice(localeName.length + 1);

    return (
        <FeedItemShell
            item={item}
            avatar={<LocaleTile localeName={localeName} />}
            whoLine={
                <>
                    <Text style={{ fontWeight: "700" }}>{localeName}</Text> {tail}
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
