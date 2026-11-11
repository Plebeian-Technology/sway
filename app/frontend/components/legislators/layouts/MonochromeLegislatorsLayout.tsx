// @lat: [[legislator-directory-layouts#MonochromeLegislatorsLayout.tsx]]

import { Link } from "@inertiajs/react";
import { ArrowRight } from "lucide-react";
import React from "react";

import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { PREFETCH_CACHE_FOR, ROUTES } from "app/frontend/sway_constants";
import { toFormattedLocaleName } from "app/frontend/sway_utils";
import { formatTermWindow } from "app/frontend/sway_utils/termWindow";
import LegislatorCard from "app/frontend/components/legislators/LegislatorCard";
import MountWhenNear from "app/frontend/components/MountWhenNear";
import { Button } from "app/frontend/components/ui/button";
import { Label } from "app/frontend/components/ui/label";
import SwayLocalePicker from "app/frontend/components/locales/SwayLocalePicker";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "app/frontend/components/ui/tabs";
import type { ILegislatorsLayoutProps } from "app/frontend/components/legislators/layouts/types";

import "app/frontend/components/legislators/layouts/MonochromeLegislatorsLayout.css";

// @lat: [[legislator-card-mounting#The threshold is a count of cards]]
const ABOVE_FOLD_COUNT = 8;

const MonochromeLegislatorsLayout: React.FC<ILegislatorsLayoutProps> = ({
    activeLegislators,
    activeTab,
    onTabChange,
    currentLocale,
    localeOptions,
    selectedLocaleId,
    onLocaleChange,
    waitingForNewTerm,
    onFindLegislators,
    currentHistory,
    isHistoryLoading,
    historyFailed,
    onRetryHistory,
    termRange,
}) => {
    const formattedSwayLocaleName = toFormattedLocaleName(currentLocale?.name ?? "");

    return (
        <div className="monochrome-legislators space-y-6">
            <header className="monochrome-legislators__header space-y-2">
                <h1 className="monochrome-legislators__title">Representatives</h1>
                <p className="monochrome-legislators__count" data-testid="legislators-count-line">
                    {activeLegislators.length
                        ? `Showing ${activeLegislators.length} representatives for ${formattedSwayLocaleName}.`
                        : waitingForNewTerm
                          ? PARITY_COPY.legislators.waitingForNewTerm(formattedSwayLocaleName)
                          : PARITY_COPY.legislators.noneFound(formattedSwayLocaleName)}
                </p>
                {termRange && (
                    <p
                        className="monochrome-legislators__term-range font-mono"
                        data-testid="legislators-term-year-range"
                    >
                        {termRange}
                    </p>
                )}
            </header>

            <section className="monochrome-legislators__controls">
                <div className="monochrome-legislators__field">
                    <Label htmlFor="v2-locale" className="monochrome-legislators__label shrink-0">
                        Locale
                    </Label>
                    <SwayLocalePicker
                        id="v2-locale"
                        options={localeOptions}
                        value={selectedLocaleId}
                        onChange={onLocaleChange}
                        className="min-w-0 flex-1"
                    />
                </div>
                <Link
                    href={ROUTES.billOfTheMonth}
                    prefetch="hover"
                    cacheFor={PREFETCH_CACHE_FOR}
                    viewTransition
                    className="inline-flex w-full shrink-0 items-center justify-center gap-2 whitespace-nowrap border border-foreground px-4 py-2 font-mono text-xs font-bold uppercase tracking-wider text-foreground transition hover:bg-foreground hover:text-background sm:w-auto"
                >
                    Start voting
                    <ArrowRight className="size-4" />
                </Link>
            </section>

            {!activeLegislators.length && !waitingForNewTerm && (
                <Button type="button" variant="outline" className="w-full" onClick={onFindLegislators}>
                    {PARITY_COPY.legislators.searchAgain}
                </Button>
            )}

            <Tabs value={activeTab} onValueChange={onTabChange}>
                <TabsList>
                    <TabsTrigger value="current">{PARITY_COPY.legislators.tabCurrentTerm}</TabsTrigger>
                    <TabsTrigger value="lifetime">{PARITY_COPY.legislators.tabLifetime}</TabsTrigger>
                    <TabsTrigger value="history">{PARITY_COPY.legislators.tabHistory}</TabsTrigger>
                </TabsList>

                {activeTab !== "history" && (
                    <div role="tabpanel" className="monochrome-legislators__roster">
                        {activeLegislators.map((legislator, index) =>
                            index < ABOVE_FOLD_COUNT ? (
                                <div key={legislator.external_id} className="monochrome-legislators__entry">
                                    <LegislatorCard
                                        legislator={legislator}
                                        mode={activeTab === "lifetime" ? "lifetime" : "current"}
                                    />
                                </div>
                            ) : (
                                <MountWhenNear key={legislator.external_id}>
                                    <div className="monochrome-legislators__entry">
                                        <LegislatorCard
                                            legislator={legislator}
                                            mode={activeTab === "lifetime" ? "lifetime" : "current"}
                                        />
                                    </div>
                                </MountWhenNear>
                            ),
                        )}
                    </div>
                )}

                <TabsContent
                    value="history"
                    data-testid="legislators-history-tab"
                    className="monochrome-legislators__roster"
                >
                    {isHistoryLoading && (
                        <p className="py-6 text-center text-sm text-muted-foreground">
                            {PARITY_COPY.legislators.loading}
                        </p>
                    )}

                    {!isHistoryLoading && historyFailed && !currentHistory && (
                        <div
                            className="monochrome-legislators__notice space-y-3"
                            data-testid="legislators-history-error"
                        >
                            <p className="text-sm font-semibold">{PARITY_COPY.legislators.historyLoadError}</p>
                            <Button
                                type="button"
                                variant="outline"
                                onClick={onRetryHistory}
                                data-testid="legislators-history-retry-button"
                            >
                                {PARITY_COPY.legislators.historyRetry}
                            </Button>
                        </div>
                    )}

                    {!isHistoryLoading && currentHistory && currentHistory.sessions.length === 0 && (
                        <div
                            className="monochrome-legislators__notice space-y-1"
                            data-testid="legislators-history-empty"
                        >
                            <p className="text-sm font-semibold">{PARITY_COPY.legislators.historyEmptyHeading}</p>
                            <p className="text-sm text-muted-foreground">{PARITY_COPY.legislators.historyEmptyBody}</p>
                        </div>
                    )}

                    {!isHistoryLoading &&
                        currentHistory &&
                        currentHistory.sessions.map((session) => (
                            <div key={session.session_label} className="space-y-4">
                                <h2 className="text-xs font-bold uppercase tracking-widest text-muted-foreground font-mono">
                                    {session.session_label}
                                </h2>
                                <div className="space-y-4">
                                    {session.entries.map((entry) => (
                                        <div
                                            key={`${session.session_label}-${entry.legislator.external_id}`}
                                            className="monochrome-legislators__entry"
                                        >
                                            <LegislatorCard
                                                legislator={entry.legislator}
                                                historyEntry={{
                                                    score: entry.score,
                                                    termWindow: formatTermWindow(entry.term) ?? "",
                                                }}
                                            />
                                        </div>
                                    ))}
                                </div>
                            </div>
                        ))}
                </TabsContent>
            </Tabs>
        </div>
    );
};

export default MonochromeLegislatorsLayout;
