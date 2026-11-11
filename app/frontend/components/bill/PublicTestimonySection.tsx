import React, { useState } from "react";
import type { sway } from "sway";

import BrowseTestimonyModal, { TStanceFilter } from "app/frontend/components/bill/BrowseTestimonyModal";
import { Button } from "app/frontend/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

interface IProps {
    counts?: sway.IPublicTestimonyCounts | null;
    letters?: sway.IPublicTestimonyLetter[] | null;
    billTitle?: string;
    billId?: number;
    canOverrideStance?: boolean;
}

// @lat: [[testimony-letters#Presenting public testimony on bill pages]]
const PublicTestimonySection: React.FC<IProps> = ({ counts, letters, billTitle, billId, canOverrideStance }) => {
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [modalFilter, setModalFilter] = useState<TStanceFilter>("all");

    if (!counts || counts.total === 0) {
        return null;
    }

    const handleOpenModal = (filter: TStanceFilter) => {
        setModalFilter(filter);
        setIsModalOpen(true);
    };

    return (
        <>
            <Card className="bg-card/95" data-testid="public-testimony-section">
                <CardHeader className="space-y-1">
                    <CardTitle className="text-xl font-black">{PARITY_COPY.publicTestimony.section.heading}</CardTitle>
                    <p className="text-sm text-muted-foreground">
                        {PARITY_COPY.publicTestimony.section.subtitle(counts.total)}
                    </p>
                </CardHeader>
                <CardContent className="space-y-4">
                    <div className="flex flex-wrap items-center gap-2">
                        <button
                            type="button"
                            onClick={() => handleOpenModal("support")}
                            className="inline-flex cursor-pointer items-center gap-1.5 rounded-full border-neo border-success bg-success/12 px-3 py-1 text-xs font-semibold tabular-nums text-success shadow-sm transition hover:bg-success/20 focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none"
                            data-testid="pill-support"
                        >
                            <span className="font-bold">{counts.support}</span>{" "}
                            {PARITY_COPY.publicTestimony.section.supportPill}
                        </button>
                        <button
                            type="button"
                            onClick={() => handleOpenModal("oppose")}
                            className="inline-flex cursor-pointer items-center gap-1.5 rounded-full border-neo border-destructive bg-destructive/12 px-3 py-1 text-xs font-semibold tabular-nums text-destructive shadow-sm transition hover:bg-destructive/20 focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none"
                            data-testid="pill-oppose"
                        >
                            <span className="font-bold">{counts.oppose}</span>{" "}
                            {PARITY_COPY.publicTestimony.section.opposePill}
                        </button>
                        <button
                            type="button"
                            onClick={() => handleOpenModal("neutral")}
                            className="inline-flex cursor-pointer items-center gap-1.5 rounded-full border-neo border-border-strong bg-surface-2 px-3 py-1 text-xs font-semibold tabular-nums text-foreground shadow-sm transition hover:bg-surface-3 focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none"
                            data-testid="pill-neutral"
                        >
                            <span className="font-bold">{counts.neutral}</span>{" "}
                            {PARITY_COPY.publicTestimony.section.neutralPill}
                        </button>
                    </div>

                    <div>
                        <Button
                            type="button"
                            variant="outline"
                            onClick={() => handleOpenModal("all")}
                            data-testid="btn-browse-public-testimony"
                            className="cursor-pointer"
                        >
                            {PARITY_COPY.publicTestimony.section.browseButton}
                        </Button>
                    </div>
                </CardContent>
            </Card>

            <BrowseTestimonyModal
                isOpen={isModalOpen}
                onClose={() => setIsModalOpen(false)}
                counts={counts}
                letters={letters}
                billTitle={billTitle}
                initialFilter={modalFilter}
                billId={billId}
                canOverrideStance={canOverrideStance}
            />
        </>
    );
};

export default PublicTestimonySection;
