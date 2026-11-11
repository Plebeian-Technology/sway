import { Link } from "@inertiajs/react";
import { ChevronDown, ChevronUp } from "lucide-react";
import { useCallback, useState } from "react";

import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { PREFETCH_CACHE_FOR, ROUTES } from "app/frontend/sway_constants";

import LegislatorChartsPanel from "app/frontend/components/legislators/charts/LegislatorChartsPanel";
import LegislatorScoreTiles from "app/frontend/components/legislators/LegislatorScoreTiles";
import { Badge } from "app/frontend/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { sway } from "sway";

// @lat: [[legislators-tab-switching-design#LegislatorCard.tsx's mode and historyEntry props]]
interface IProps {
    legislator: sway.ILegislator;
    mode?: "current" | "lifetime";
    historyEntry?: {
        score: sway.scoring.IAgreeable;
        termWindow: string;
    };
}

const DEFAULT_AVATAR = "/images/politician.svg";

const LegislatorCard: React.FC<IProps> = ({ legislator, mode = "current", historyEntry }) => {
    const href = ROUTES.legislator(legislator.id);
    const score = historyEntry
        ? historyEntry.score
        : mode === "lifetime"
          ? legislator.lifetime_score
          : legislator.user_legislator_score;
    const [avatarSrc, setAvatarSrc] = useState(legislator.photo_url || DEFAULT_AVATAR);
    const [chartsOpen, setChartsOpen] = useState(false);
    const handleAvatarError = useCallback(() => setAvatarSrc(DEFAULT_AVATAR), []);
    const toggleCharts = useCallback(() => setChartsOpen((v) => !v), []);
    // @lat: [[legislators-tab-switching-design#LegislatorCard.tsx's mode and historyEntry props]]
    const districtLabel =
        legislator.district?.name ||
        (typeof legislator.district?.number === "number" ? `District ${legislator.district.number}` : null);

    return (
        <Card className="bg-card/95">
            <CardHeader className="gap-3">
                <div className="flex flex-wrap items-center gap-2">
                    <CardTitle className="text-2xl font-black">{legislator.full_name}</CardTitle>
                    {historyEntry && (
                        <Badge variant="stamp" tone="neutral" data-testid="legislator-card-ended-stamp">
                            {PARITY_COPY.legislators.endedStamp}
                        </Badge>
                    )}
                </div>
                <p className="text-sm font-semibold uppercase tracking-widest text-muted-foreground">
                    {legislator.title} · {districtLabel}
                    {historyEntry ? ` · ${historyEntry.termWindow}` : null}
                </p>
            </CardHeader>

            <CardContent className="grid gap-5 md:grid-cols-[10rem_minmax(0,1fr)] md:items-start">
                <div className="flex justify-center md:justify-start">
                    <div className="w-full max-w-[10rem] rounded-lg border-neo border-border-strong bg-surface-2 p-1 shadow-neo">
                        <img
                            src={avatarSrc}
                            alt={legislator.full_name}
                            aria-label={`${legislator.full_name} avatar`}
                            className="aspect-[4/5] w-full rounded-lg object-cover"
                            onError={avatarSrc === DEFAULT_AVATAR ? undefined : handleAvatarError}
                        />
                    </div>
                </div>

                <div className="min-w-0 space-y-3 text-sm leading-6 text-muted-foreground">
                    {legislator.email && <p className="break-words">Email: {legislator.email}</p>}
                    {legislator.phone && <p>Phone: {legislator.phone}</p>}
                    <LegislatorScoreTiles score={score} />
                    <div className="flex flex-wrap items-center gap-3 pt-1">
                        <Link
                            href={href}
                            prefetch="click"
                            cacheFor={PREFETCH_CACHE_FOR}
                            viewTransition
                            className="inline-flex h-9 cursor-pointer items-center rounded-xl border-neo border-border-strong bg-primary px-4 text-sm font-semibold text-primary-foreground shadow-neo transition"
                        >
                            View representative
                        </Link>

                        {score && !historyEntry && (
                            <button
                                type="button"
                                onClick={toggleCharts}
                                aria-expanded={chartsOpen}
                                aria-controls={`legislator-charts-${legislator.external_id}`}
                                className="inline-flex h-9 cursor-pointer items-center gap-2 rounded-xl border-neo border-border-strong bg-surface-2 px-3 text-xs font-black uppercase tracking-widest text-foreground shadow-neo transition"
                            >
                                {chartsOpen ? PARITY_COPY.legislators.hideCharts : PARITY_COPY.legislators.showCharts}
                                {chartsOpen ? (
                                    <ChevronUp className="size-3.5" aria-hidden="true" />
                                ) : (
                                    <ChevronDown className="size-3.5" aria-hidden="true" />
                                )}
                            </button>
                        )}
                    </div>

                    {score && !historyEntry && chartsOpen && (
                        <div id={`legislator-charts-${legislator.external_id}`} className="pt-1">
                            <LegislatorChartsPanel legislator={legislator} mode={mode} />
                        </div>
                    )}
                </div>
            </CardContent>
        </Card>
    );
};

export default LegislatorCard;
