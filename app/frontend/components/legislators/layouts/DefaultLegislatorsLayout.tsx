// @lat: [[legislator-directory-layouts#DefaultLegislatorsLayout.tsx]]

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

// @lat: [[legislator-card-mounting#The threshold is a count of cards]]
const ABOVE_FOLD_COUNT = 8;

const DefaultLegislatorsLayout: React.FC<ILegislatorsLayoutProps> = ({
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
        <div className="space-y-6">
            <div className="flex flex-col gap-3 rounded-xl border border-border bg-surface-2 px-4 py-3 sm:flex-row sm:items-center">
                <div className="flex min-w-0 flex-1 items-center gap-3">
                    <Label htmlFor="v2-locale" className="shrink-0">
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
                    className="inline-flex w-full shrink-0 items-center justify-center gap-2 whitespace-nowrap rounded-xl border-neo border-border-strong bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground shadow-neo transition sm:w-auto"
                >
                    Start voting
                    <ArrowRight className="size-4" />
                </Link>
            </div>

            {!activeLegislators.length && !waitingForNewTerm && (
                <Button type="button" variant="outline" className="w-full" onClick={onFindLegislators}>
                    {PARITY_COPY.legislators.searchAgain}
                </Button>
            )}
            <div>
                <div className="space-y-4">
                    <h1 className="text-xl font-black sm:text-2xl">Representatives</h1>
                    <p className="text-sm text-muted-foreground" data-testid="legislators-count-line">
                        {activeLegislators.length
                            ? `Showing ${activeLegislators.length} representatives for ${formattedSwayLocaleName}.`
                            : waitingForNewTerm
                              ? PARITY_COPY.legislators.waitingForNewTerm(formattedSwayLocaleName)
                              : PARITY_COPY.legislators.noneFound(formattedSwayLocaleName)}
                    </p>

                    <Tabs value={activeTab} onValueChange={onTabChange}>
                        <TabsList>
                            <TabsTrigger value="current">{PARITY_COPY.legislators.tabCurrentTerm}</TabsTrigger>
                            <TabsTrigger value="lifetime">{PARITY_COPY.legislators.tabLifetime}</TabsTrigger>
                            <TabsTrigger value="history">{PARITY_COPY.legislators.tabHistory}</TabsTrigger>
                        </TabsList>

                        {termRange && (
                            <p
                                className="-mt-2 text-xs text-muted-foreground"
                                data-testid="legislators-term-year-range"
                            >
                                {termRange}
                            </p>
                        )}

                        {activeTab !== "history" && (
                            <div role="tabpanel" className="space-y-4">
                                {activeLegislators.map((legislator, index) =>
                                    index < ABOVE_FOLD_COUNT ? (
                                        <LegislatorCard
                                            key={legislator.external_id}
                                            legislator={legislator}
                                            mode={activeTab === "lifetime" ? "lifetime" : "current"}
                                        />
                                    ) : (
                                        <MountWhenNear key={legislator.external_id}>
                                            <LegislatorCard
                                                legislator={legislator}
                                                mode={activeTab === "lifetime" ? "lifetime" : "current"}
                                            />
                                        </MountWhenNear>
                                    ),
                                )}
                            </div>
                        )}

                        <TabsContent value="history" data-testid="legislators-history-tab" className="space-y-6">
                            {isHistoryLoading && (
                                <p className="py-6 text-center text-sm text-muted-foreground">
                                    {PARITY_COPY.legislators.loading}
                                </p>
                            )}

                            {!isHistoryLoading && historyFailed && !currentHistory && (
                                <div
                                    className="space-y-3 rounded-xl border-neo border-border-strong bg-surface-2 px-4 py-8 text-center"
                                    data-testid="legislators-history-error"
                                >
                                    <p className="text-sm font-semibold text-foreground">
                                        {PARITY_COPY.legislators.historyLoadError}
                                    </p>
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
                                    className="space-y-1 rounded-xl border-neo border-border-strong bg-surface-2 px-4 py-8 text-center"
                                    data-testid="legislators-history-empty"
                                >
                                    <p className="text-sm font-semibold text-foreground">
                                        {PARITY_COPY.legislators.historyEmptyHeading}
                                    </p>
                                    <p className="text-sm text-muted-foreground">
                                        {PARITY_COPY.legislators.historyEmptyBody}
                                    </p>
                                </div>
                            )}

                            {!isHistoryLoading &&
                                currentHistory &&
                                currentHistory.sessions.map((session) => (
                                    <div key={session.session_label} className="space-y-4">
                                        <h2 className="text-xs font-black uppercase tracking-widest text-muted-foreground">
                                            {session.session_label}
                                        </h2>
                                        <div className="space-y-4">
                                            {session.entries.map((entry) => (
                                                <LegislatorCard
                                                    key={`${session.session_label}-${entry.legislator.external_id}`}
                                                    legislator={entry.legislator}
                                                    historyEntry={{
                                                        score: entry.score,
                                                        termWindow: formatTermWindow(entry.term) ?? "",
                                                    }}
                                                />
                                            ))}
                                        </div>
                                    </div>
                                ))}
                        </TabsContent>
                    </Tabs>
                </div>
            </div>
        </div>
    );
};

export default DefaultLegislatorsLayout;
