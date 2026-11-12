import BillOfTheMonthReleasedItem from "app/frontend/components/feed/BillOfTheMonthReleasedItem";
import LegislativeTermBeganItem from "app/frontend/components/feed/LegislativeTermBeganItem";
import LegislatorVotedItem from "app/frontend/components/feed/LegislatorVotedItem";
import OrganizationPositionTakenItem from "app/frontend/components/feed/OrganizationPositionTakenItem";
import RepresentativesFoundItem from "app/frontend/components/feed/RepresentativesFoundItem";
import UserJoinedItem from "app/frontend/components/feed/UserJoinedItem";
import type { IFeedItem } from "app/frontend/components/feed/types";

interface IProps {
    item: IFeedItem;
}

const FeedItemRow: React.FC<IProps> = ({ item }) => {
    switch (item.kind) {
        case "bill_of_the_month_released":
            return <BillOfTheMonthReleasedItem item={item} />;
        case "legislator_voted":
            return <LegislatorVotedItem item={item} />;
        case "organization_position_taken":
            return <OrganizationPositionTakenItem item={item} />;
        case "user_joined":
            return <UserJoinedItem item={item} />;
        case "representatives_found":
            return <RepresentativesFoundItem item={item} />;
        case "legislative_term_began":
            return <LegislativeTermBeganItem item={item} />;
    }
};

export default FeedItemRow;
