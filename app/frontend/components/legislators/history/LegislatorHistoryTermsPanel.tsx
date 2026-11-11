import React, { useMemo } from "react";
import { Calendar } from "lucide-react";

import LegislatorTermCard from "app/frontend/components/legislators/history/LegislatorTermCard";
import { Badge } from "app/frontend/components/ui/badge";
import { ILegislatorHistoryTermsPanelProps } from "app/frontend/types/legislators";

// @lat: [[legislator-history-serialization#Read-only historical term agreement serialization]]
const LegislatorHistoryTermsPanel: React.FC<ILegislatorHistoryTermsPanelProps> = ({ legislator, terms }) => {
    const sortedTerms = useMemo(() => {
        return (terms ?? []).slice().sort((a, b) => b.term_start_year - a.term_start_year);
    }, [terms]);

    if (sortedTerms.length === 0) {
        return (
            <div
                data-testid="legislator-history-empty"
                className="space-y-3 rounded-2xl border-neo border-border-strong bg-surface-2 p-8 text-center shadow-neo"
            >
                <Calendar className="mx-auto size-10 text-muted-foreground" aria-hidden="true" />
                <h3 className="text-base font-black text-foreground">No historical terms on record</h3>
                <p className="text-sm text-muted-foreground">
                    Historical term records and voting score breakdowns are not yet available for this official.
                </p>
            </div>
        );
    }

    return (
        <div className="space-y-5">
            <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
                <div>
                    <h3 className="text-base font-black text-foreground">Legislative Service History</h3>
                    <p className="text-xs text-muted-foreground">
                        Review voting agreement by legislative session. Each term reflects recorded community and
                        personal agreement during that representative's service period.
                    </p>
                </div>
                <Badge variant="stamp" tone="neutral" className="self-start sm:self-auto">
                    {sortedTerms.length} {sortedTerms.length === 1 ? "Term" : "Terms"}
                </Badge>
            </div>

            <div data-testid="legislator-history-terms-list" className="space-y-5">
                {sortedTerms.map((term) => (
                    <LegislatorTermCard key={term.id} term={term} legislator={legislator} />
                ))}
            </div>
        </div>
    );
};

export default LegislatorHistoryTermsPanel;
