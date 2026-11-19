import React from "react";
import { Text } from "react-native";

import { PARITY_COPY } from "../../../../app/frontend/sway_constants/parityCopy";
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

const resolvePositionVerb = (support: string): string => {
    if (support === "Support") return PARITY_COPY.feed.organizationPositionVerbs.Support;
    if (support === "Oppose") return PARITY_COPY.feed.organizationPositionVerbs.Oppose;
    return PARITY_COPY.feed.organizationPositionVerbs.Neutral;
};

const OrganizationPositionTakenItem: React.FC<IProps> = ({ item, onPressBill, onShareBill }) => {
    const organization = item.organization;
    const localeName = item.sway_locale?.name ?? "";

    if (!organization) {
        return null;
    }

    const positionVerb = resolvePositionVerb(organization.support);

    return (
        <FeedItemShell
            item={item}
            subject="organization"
            avatar={<FeedAvatar kind="organization" organizationName={organization.name} />}
            whoLine={
                <>
                    <Text style={{ fontFamily: "OpenSans-SemiBold" }}>{organization.name}</Text>{" "}
                    {PARITY_COPY.feed.organizationPositionTaken(positionVerb, localeName)}
                </>
            }
        >
            {item.bill ? (
                <>
                    <FeedBillBlock bill={item.bill} onPressBill={onPressBill} />
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

export default OrganizationPositionTakenItem;
