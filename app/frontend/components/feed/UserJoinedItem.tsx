import SwayLogo from "app/frontend/components/SwayLogo";
import FeedItemShell from "app/frontend/components/feed/FeedItemShell";
import type { IFeedItem } from "app/frontend/components/feed/types";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

interface IProps {
    item: IFeedItem;
}

const UserJoinedItem: React.FC<IProps> = ({ item }) => (
    <FeedItemShell
        item={item}
        avatar={<SwayLogo className="size-11 object-contain" maxWidth={44} />}
        whoLine={
            <>
                <strong className="font-semibold">{PARITY_COPY.feed.userJoinedActor}</strong>{" "}
                {PARITY_COPY.feed.userJoinedAction}
            </>
        }
    >
        <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{PARITY_COPY.feed.userJoinedSummary}</p>
    </FeedItemShell>
);

export default UserJoinedItem;
