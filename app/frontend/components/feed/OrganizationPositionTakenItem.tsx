import { OrganizationTile } from "app/frontend/components/feed/FeedAvatar";
import { FeedBillActions, FeedBillBlock } from "app/frontend/components/feed/FeedBillBlock";
import FeedItemShell from "app/frontend/components/feed/FeedItemShell";
import type { IFeedItem } from "app/frontend/components/feed/types";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

interface IProps {
    item: IFeedItem;
}

const resolveStanceVerb = (support: string): string => {
    if (support === "Support") return PARITY_COPY.feed.organizationStanceVerbs.Support;
    if (support === "Oppose") return PARITY_COPY.feed.organizationStanceVerbs.Oppose;
    return PARITY_COPY.feed.organizationStanceVerbs.Neutral;
};

const OrganizationPositionTakenItem: React.FC<IProps> = ({ item }) => {
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
                    <strong className="font-semibold">{organization.name}</strong>{" "}
                    {PARITY_COPY.feed.organizationPositionTaken(stanceVerb, localeName)}
                </>
            }
        >
            {item.bill && (
                <>
                    <FeedBillBlock bill={item.bill} />
                    <FeedBillActions bill={item.bill} userSupport={item.user_support} />
                </>
            )}
        </FeedItemShell>
    );
};

export default OrganizationPositionTakenItem;
