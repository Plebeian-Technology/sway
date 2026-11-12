import React from "react";
import { Text } from "react-native";

import { PARITY_COPY } from "../../../../app/frontend/sway_constants/parityCopy";
import { OrganizationTile } from "./FeedAvatar";
import { FeedBillActions, FeedBillBlock } from "./FeedBillBlock";
import FeedItemShell from "./FeedItemShell";
import type { IFeedBill, IFeedItem } from "./types";

interface IProps {
    item: IFeedItem;
    onPressBill: (billId: number) => void;
    onShareBill: (bill: IFeedBill) => void;
}

const resolveStanceVerb = (support: string): string => {
    if (support === "Support") return PARITY_COPY.feed.organizationStanceVerbs.Support;
    if (support === "Oppose") return PARITY_COPY.feed.organizationStanceVerbs.Oppose;
    return PARITY_COPY.feed.organizationStanceVerbs.Neutral;
};

const OrganizationPositionTakenItem: React.FC<IProps> = ({ item, onPressBill, onShareBill }) => {
    const organization = item.organization;
    const localeName = item.sway_locale?.name ?? "";

    if (!organization) {
        return null;
    }

    const stanceVerb = resolveStanceVerb(organization.support);

    return (
        <FeedItemShell
            item={item}
            avatar={<OrganizationTile name={organization.name} />}
            whoLine={
                <>
                    <Text style={{ fontWeight: "700" }}>{organization.name}</Text>{" "}
                    {PARITY_COPY.feed.organizationPositionTaken(stanceVerb, localeName)}
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
