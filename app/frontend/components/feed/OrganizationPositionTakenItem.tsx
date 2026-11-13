import FeedAvatar from "app/frontend/components/feed/FeedAvatar";
import FeedBillActions from "app/frontend/components/feed/FeedBillActions";
import FeedBillBlock from "app/frontend/components/feed/FeedBillBlock";
import FeedItemShell from "app/frontend/components/feed/FeedItemShell";
import type { IFeedItem } from "app/frontend/components/feed/types";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

interface IProps {
    item: IFeedItem;
}

const resolvePositionVerb = (support: string): string => {
    if (support === "Support") return PARITY_COPY.feed.organizationPositionVerbs.Support;
    if (support === "Oppose") return PARITY_COPY.feed.organizationPositionVerbs.Oppose;
    return PARITY_COPY.feed.organizationPositionVerbs.Neutral;
};

const OrganizationPositionTakenItem: React.FC<IProps> = ({ item }) => {
    const organization = item.organization;
    const localeName = item.sway_locale?.name ?? "";

    if (!organization) {
        return null;
    }

    const positionVerb = resolvePositionVerb(organization.support);

    return (
        <FeedItemShell
            item={item}
            avatar={<FeedAvatar kind="organization" organizationName={organization.name} />}
            whoLine={
                <>
                    <strong className="font-semibold">{organization.name}</strong>{" "}
                    {PARITY_COPY.feed.organizationPositionTaken(positionVerb, localeName)}
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
