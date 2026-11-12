import { Head, InfiniteScroll } from "@inertiajs/react";

import FeedItemRow from "app/frontend/components/feed/FeedItemRow";
import { groupFeedItemsByDate } from "app/frontend/components/feed/dateGrouping";
import type { IFeedItem } from "app/frontend/components/feed/types";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

interface IProps {
    items: IFeedItem[];
    feed_search?: string | null;
}

const Feed: React.FC<IProps> = ({ items }) => {
    const groups = groupFeedItemsByDate(items);

    return (
        <>
            <Head title={PARITY_COPY.feed.title} />
            <div className="mx-auto w-full max-w-2xl">
                {items.length === 0 ? (
                    <div className="rounded-md border border-border bg-card px-6 py-12 text-center text-sm text-muted-foreground">
                        {PARITY_COPY.feed.emptyState}
                    </div>
                ) : (
                    <InfiniteScroll
                        data="items"
                        preserveUrl
                        loading={
                            <div className="py-6 text-center text-sm text-muted-foreground">
                                {PARITY_COPY.feed.loadingMore}
                            </div>
                        }
                    >
                        {groups.map((group, index) => (
                            <section key={`${group.heading}-${index}`}>
                                <h2 className="border-b border-border bg-background px-5 pt-7 pb-2.5 text-sm font-semibold text-foreground">
                                    {group.heading}
                                </h2>
                                {group.items.map((item) => (
                                    <FeedItemRow key={item.key} item={item} />
                                ))}
                            </section>
                        ))}
                    </InfiniteScroll>
                )}
            </div>
        </>
    );
};

export default Feed;
