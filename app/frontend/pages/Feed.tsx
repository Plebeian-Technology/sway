import { Head, InfiniteScroll, Link, router, usePoll } from "@inertiajs/react";
import { useState } from "react";

import FeedItemRow from "app/frontend/components/feed/FeedItemRow";
import FeedSearchBar from "app/frontend/components/feed/FeedSearchBar";
import ShowNewFeedItemsButton from "app/frontend/components/feed/ShowNewFeedItemsButton";
import { groupFeedItemsByDate } from "app/frontend/components/feed/dateGrouping";
import type { IFeedItem } from "app/frontend/components/feed/types";
import { useDebouncedUrlSearch } from "app/frontend/hooks/useDebouncedUrlSearch";
import { useFeedSubscription } from "app/frontend/hooks/useFeedSubscription";
import { ROUTES } from "app/frontend/sway_constants";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

interface IProps {
    items: IFeedItem[];
    feed_search?: string | null;
    newest_keys?: string[];
}

const FEED_PAGE_SIZE = 20;
const FEED_SEARCH_ONLY = ["items", "feed_search"];
const FEED_SEARCH_RESET_PARAMS = ["feed_cursor"];
const FEED_SEARCH_RESET = ["items"];
const NEWEST_KEYS_ONLY = ["newest_keys"];
const NEWEST_KEYS_POLL_OPTIONS = { only: NEWEST_KEYS_ONLY };
const NEWEST_KEYS_POLL_CONFIG = { background: "pause" as const };
const REFRESH_FEED_OPTIONS = {
    only: ["items", "newest_keys"],
    reset: ["items"],
    preserveState: true,
};

const Feed: React.FC<IProps> = ({ items, feed_search, newest_keys }) => {
    const [dismissedNewestKeys, setDismissedNewestKeys] = useState<string[] | undefined>(undefined);

    useFeedSubscription();
    usePoll(60000, NEWEST_KEYS_POLL_OPTIONS, NEWEST_KEYS_POLL_CONFIG);

    const { value: searchValue, onChange: onSearchChange } = useDebouncedUrlSearch({
        only: FEED_SEARCH_ONLY,
        resetParams: FEED_SEARCH_RESET_PARAMS,
        reset: FEED_SEARCH_RESET,
        errorTitle: PARITY_COPY.feed.searchError,
        param: "feed_search",
    });

    const activeQuery = feed_search?.trim() ?? "";
    const isSearching = activeQuery.length > 0;
    const shownKeys = new Set(items.map((item) => item.key));
    const activeNewestKeys = newest_keys && newest_keys !== dismissedNewestKeys ? newest_keys : [];
    const newCount = activeNewestKeys.filter((key) => !shownKeys.has(key)).length;
    const isCapped = activeNewestKeys.length === FEED_PAGE_SIZE && newCount === activeNewestKeys.length;
    const groups = groupFeedItemsByDate(items);

    const handleShowNew = () => {
        setDismissedNewestKeys(newest_keys);
        window.scrollTo({ top: 0, behavior: "smooth" });
        router.get(ROUTES.feed, activeQuery ? { feed_search: activeQuery } : {}, REFRESH_FEED_OPTIONS);
    };

    return (
        <>
            <Head title={PARITY_COPY.feed.title} />
            <div className="mx-auto w-full max-w-2xl">
                <FeedSearchBar value={searchValue} onChange={onSearchChange} />
                <ShowNewFeedItemsButton newCount={newCount} isCapped={isCapped} onClick={handleShowNew} />

                {isSearching && items.length > 0 && (
                    <p className="border-b border-border px-5 py-4 text-sm text-muted-foreground" aria-live="polite">
                        {PARITY_COPY.feed.searchMatchCount(items.length, activeQuery)}
                    </p>
                )}

                {items.length === 0 ? (
                    <div
                        className="rounded-md border border-border bg-card px-6 py-12 text-center text-sm text-muted-foreground"
                        aria-live={isSearching ? "polite" : undefined}
                    >
                        {isSearching ? (
                            <>
                                <p>{PARITY_COPY.feed.searchNoMatches(activeQuery)}</p>
                                <p className="mt-2">
                                    {PARITY_COPY.feed.searchBrowsePrefix}
                                    <Link
                                        href={ROUTES.bills}
                                        className="text-primary underline-offset-4 hover:underline"
                                    >
                                        {PARITY_COPY.feed.searchBrowseLink}
                                    </Link>
                                    .
                                </p>
                            </>
                        ) : (
                            PARITY_COPY.feed.emptyState
                        )}
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
                        {isSearching && (
                            <p className="px-6 py-7 text-center text-sm text-muted-foreground">
                                {PARITY_COPY.feed.searchBrowsePrefix}
                                <Link href={ROUTES.bills} className="text-primary underline-offset-4 hover:underline">
                                    {PARITY_COPY.feed.searchBrowseLink}
                                </Link>
                                .
                            </p>
                        )}
                    </InfiniteScroll>
                )}
            </div>
        </>
    );
};

export default Feed;
