import React from "react";

import BillOfTheMonthReleasedItem from "./BillOfTheMonthReleasedItem";
import LegislativeTermBeganItem from "./LegislativeTermBeganItem";
import LegislatorVotedItem from "./LegislatorVotedItem";
import OrganizationPositionTakenItem from "./OrganizationPositionTakenItem";
import RepresentativesFoundItem from "./RepresentativesFoundItem";
import UserJoinedItem from "./UserJoinedItem";
import type { IFeedBill, IFeedItem } from "./types";

interface IProps {
    item: IFeedItem;
    onPressBill: (billId: number) => void;
    onShareBill: (bill: IFeedBill) => void;
    onPressLegislators: () => void;
}

const FeedItemRow: React.FC<IProps> = ({ item, onPressBill, onShareBill, onPressLegislators }) => {
    switch (item.kind) {
        case "bill_of_the_month_released":
            return <BillOfTheMonthReleasedItem item={item} onPressBill={onPressBill} onShareBill={onShareBill} />;
        case "legislator_voted":
            return <LegislatorVotedItem item={item} onPressBill={onPressBill} onShareBill={onShareBill} />;
        case "organization_position_taken":
            return <OrganizationPositionTakenItem item={item} onPressBill={onPressBill} onShareBill={onShareBill} />;
        case "user_joined":
            return <UserJoinedItem item={item} />;
        case "representatives_found":
            return <RepresentativesFoundItem item={item} onPressLegislators={onPressLegislators} />;
        case "legislative_term_began":
            return <LegislativeTermBeganItem item={item} />;
    }
};

export default FeedItemRow;
