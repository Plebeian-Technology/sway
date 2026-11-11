import React, { useState } from "react";
import { Link } from "@inertiajs/react";
import { ChevronDown, ChevronUp, Info, Vote } from "lucide-react";
import { sway } from "sway";

import VoterAgreementChart from "app/frontend/components/legislators/charts/VoterAgreementChart";
import VoterDistrictAgreementChart from "app/frontend/components/legislators/charts/VoterDistrictAgreementChart";
import HistoricalRepairModal from "app/frontend/components/legislators/history/HistoricalRepairModal";
import { Badge } from "app/frontend/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { useUser } from "app/frontend/hooks/users/useUser";
import { ILegislatorTermCardProps } from "app/frontend/types/legislators";

interface IAgreementCalc {
    displayPct: string;
    agreed: number;
    disagreed: number;
    noVote: number;
    abstained: number;
    total: number;
}

function calculateAgreement(score: sway.scoring.IAgreeable | null | undefined): IAgreementCalc {
    if (!score) {
        return {
            displayPct: "--%",
            agreed: 0,
            disagreed: 0,
            noVote: 0,
            abstained: 0,
            total: 0,
        };
    }
    const agreed = Number(score.count_agreed || 0);
    const disagreed = Number(score.count_disagreed || 0);
    const noVote = Number(score.count_no_legislator_vote || 0);
    const abstained = Number(score.count_legislator_abstained || 0);
    const total = agreed + disagreed;
    if (total === 0) {
        return {
            displayPct: "--%",
            agreed,
            disagreed,
            noVote,
            abstained,
            total: 0,
        };
    }
    const pct = Math.round((agreed / total) * 100);
    return {
        displayPct: `${pct}%`,
        agreed,
        disagreed,
        noVote,
        abstained,
        total,
    };
}

// @lat: [[legislator-history-serialization#Read-only historical term agreement serialization]]
// @lat: [[legislator-history-serialization#Why unvoted terms are rendered with distinct coverage indicators]]
const LegislatorTermCard: React.FC<ILegislatorTermCardProps> = ({ term, legislator }) => {
    const user = useUser();
    const [chartsOpen, setChartsOpen] = useState(false);
    const [repairModalOpen, setRepairModalOpen] = useState(false);

    const userCalc = calculateAgreement(term.user_score);
    const districtCalc = calculateAgreement(term.district_score);
    const localeCalc = calculateAgreement(term.locale_score);

    const termWindowText = `${term.term_start_year}\u2013${term.term_end_year}`;
    const districtTitle = term.district_name ?? legislator.district?.name ?? "District";

    return (
        <Card
            data-testid="legislator-term-card"
            className="overflow-hidden border-neo border-border-strong bg-card/95 shadow-neo"
        >
            <CardHeader className="space-y-3 pb-3">
                <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
                    <div className="space-y-1">
                        <CardTitle className="text-xl font-black text-foreground">{term.session_label}</CardTitle>
                        <p className="text-xs font-black uppercase tracking-widest text-muted-foreground">
                            {term.district_name ?? "At-Large"} · {termWindowText}
                        </p>
                    </div>

                    <div className="flex flex-wrap items-center gap-2">
                        {term.active ? (
                            <Badge variant="stamp" tone="success" data-testid="term-active-badge">
                                Current Term
                            </Badge>
                        ) : (
                            <Badge variant="stamp" tone="neutral" data-testid="term-past-badge">
                                Ended
                            </Badge>
                        )}

                        {term.is_executive && (
                            <Badge variant="stamp" tone="info" data-testid="term-card-executive-stamp">
                                Executive Office
                            </Badge>
                        )}

                        {term.correction_explanation && (
                            <button
                                type="button"
                                onClick={() => setRepairModalOpen(true)}
                                aria-label="View score correction audit explanation"
                                className="cursor-pointer focus:outline-hidden"
                            >
                                <Badge
                                    variant="stamp"
                                    tone="warning"
                                    className="gap-1 transition"
                                    data-testid="record-corrected-badge"
                                >
                                    <Info className="size-3" aria-hidden="true" />
                                    Record Corrected
                                </Badge>
                            </button>
                        )}
                    </div>
                </div>
            </CardHeader>

            <CardContent className="space-y-4 pt-0">
                {user ? (
                    term.user_score ? (
                        <div
                            data-testid="term-user-score-tile"
                            data-neo-surface="true"
                            className="space-y-2 rounded-xl border-neo border-border-strong bg-surface-2 p-4 shadow-neo"
                        >
                            <div className="flex items-center justify-between">
                                <div className="flex items-center gap-2">
                                    <span className="text-xs font-black uppercase tracking-widest text-muted-foreground">
                                        Your Agreement
                                    </span>
                                    <Badge variant="solid" tone="primary" className="px-2 py-0 text-[10px]">
                                        Personal
                                    </Badge>
                                </div>
                                <span className="text-xl font-black tabular-nums text-primary">
                                    {userCalc.displayPct}
                                </span>
                            </div>
                            <div className="flex flex-wrap gap-4 text-xs font-bold text-muted-foreground">
                                <span className="text-primary">{userCalc.agreed} Agreed</span>
                                <span className="text-destructive">{userCalc.disagreed} Disagreed</span>
                                {userCalc.noVote > 0 && <span>{userCalc.noVote} No Vote</span>}
                                {userCalc.abstained > 0 && <span>{userCalc.abstained} Abstained</span>}
                            </div>
                        </div>
                    ) : (
                        <div
                            data-testid="unvoted-term-notice"
                            className="flex items-start gap-3 rounded-xl border border-border bg-surface-2/80 p-4"
                        >
                            <Vote className="mt-0.5 size-5 shrink-0 text-muted-foreground" aria-hidden="true" />
                            <div className="space-y-1">
                                <h4 className="text-xs font-black uppercase tracking-widest text-foreground">
                                    No Personal Votes Recorded
                                </h4>
                                <p className="text-sm leading-normal text-muted-foreground">
                                    You have no votes on record for this term. Community agreement for this term is
                                    displayed below.
                                </p>
                            </div>
                        </div>
                    )
                ) : (
                    <div
                        data-testid="unauthenticated-history-notice"
                        className="flex flex-col justify-between gap-3 rounded-xl border border-dashed border-border-strong bg-surface-2/50 p-4 sm:flex-row sm:items-center"
                    >
                        <div className="space-y-1">
                            <h4 className="text-xs font-black uppercase tracking-widest text-foreground">
                                Compare Your Votes
                            </h4>
                            <p className="text-sm leading-normal text-muted-foreground">
                                Sign in or register with your address to see personal vote agreement against this
                                representative for this term.
                            </p>
                        </div>
                        <Link
                            href="/login"
                            className="inline-flex h-9 shrink-0 items-center justify-center rounded-xl border-neo border-border-strong bg-primary px-3 text-xs font-black uppercase tracking-widest text-primary-foreground shadow-neo transition"
                        >
                            Sign in
                        </Link>
                    </div>
                )}

                <div className="grid gap-3 sm:grid-cols-2">
                    <div
                        data-testid="term-district-score-tile"
                        data-neo-surface="true"
                        className="space-y-2 rounded-xl border-neo border-border-strong bg-surface-2 p-4 shadow-neo"
                    >
                        <div className="flex items-center justify-between">
                            <span className="text-xs font-black uppercase tracking-widest text-muted-foreground">
                                {districtTitle} Agreement
                            </span>
                            <span
                                className={`text-xl font-black tabular-nums ${districtCalc.total > 0 ? "text-foreground" : "text-muted-foreground"}`}
                            >
                                {districtCalc.total > 0 ? districtCalc.displayPct : "No votes recorded (--%)"}
                            </span>
                        </div>
                        <div className="flex flex-wrap gap-4 text-xs font-bold text-muted-foreground">
                            <span>{districtCalc.agreed} Agreed</span>
                            <span>{districtCalc.disagreed} Disagreed</span>
                            {districtCalc.noVote > 0 && <span>{districtCalc.noVote} No Vote</span>}
                        </div>
                    </div>

                    <div
                        data-testid="term-locale-score-tile"
                        data-neo-surface="true"
                        className="space-y-2 rounded-xl border-neo border-border-strong bg-surface-2 p-4 shadow-neo"
                    >
                        <div className="flex items-center justify-between">
                            <span className="text-xs font-black uppercase tracking-widest text-muted-foreground">
                                Locale Agreement
                            </span>
                            <span
                                className={`text-xl font-black tabular-nums ${localeCalc.total > 0 ? "text-foreground" : "text-muted-foreground"}`}
                            >
                                {localeCalc.total > 0 ? localeCalc.displayPct : "No votes recorded (--%)"}
                            </span>
                        </div>
                        <div className="flex flex-wrap gap-4 text-xs font-bold text-muted-foreground">
                            <span>{localeCalc.agreed} Agreed</span>
                            <span>{localeCalc.disagreed} Disagreed</span>
                            {localeCalc.noVote > 0 && <span>{localeCalc.noVote} No Vote</span>}
                        </div>
                    </div>
                </div>

                {(term.user_score || term.district_score || term.locale_score) && (
                    <div className="space-y-3 pt-1">
                        <button
                            type="button"
                            onClick={() => setChartsOpen((v) => !v)}
                            aria-expanded={chartsOpen}
                            className="inline-flex h-9 cursor-pointer items-center gap-2 rounded-xl border-neo border-border-strong bg-surface-2 px-3 text-xs font-black uppercase tracking-widest text-foreground shadow-neo transition"
                            data-testid={`term-charts-toggle-${term.id}`}
                        >
                            {chartsOpen ? "Hide term charts" : "Show term charts"}
                            {chartsOpen ? (
                                <ChevronUp className="size-3.5" aria-hidden="true" />
                            ) : (
                                <ChevronDown className="size-3.5" aria-hidden="true" />
                            )}
                        </button>

                        {chartsOpen && (
                            <div
                                className="space-y-3 rounded-xl border-neo border-border-strong bg-surface-3 p-4 shadow-neo"
                                data-testid={`term-charts-panel-${term.id}`}
                            >
                                {term.user_score && (
                                    <VoterAgreementChart
                                        scores={term.user_score}
                                        title={`Your agreement · ${term.session_label}`}
                                    />
                                )}
                                {term.district_score && (
                                    <VoterDistrictAgreementChart
                                        scores={{ legislator_id: legislator.id, ...term.district_score }}
                                        title={`${districtTitle} agreement · ${term.session_label}`}
                                    />
                                )}
                                {term.locale_score && (
                                    <VoterDistrictAgreementChart
                                        scores={{ legislator_id: legislator.id, ...term.locale_score }}
                                        title={`Locale agreement · ${term.session_label}`}
                                    />
                                )}
                            </div>
                        )}
                    </div>
                )}
            </CardContent>

            {term.correction_explanation && (
                <HistoricalRepairModal
                    explanation={term.correction_explanation}
                    term={term}
                    legislator={legislator}
                    open={repairModalOpen}
                    onOpenChange={setRepairModalOpen}
                />
            )}
        </Card>
    );
};

export default LegislatorTermCard;
