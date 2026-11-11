import { CheckCircle2 } from "lucide-react";

import { useCastUserVote } from "app/frontend/components/bill/hooks/useCastUserVote";
import ProvisionalRegistrationModal from "app/frontend/components/bill/ProvisionalRegistrationModal";
import { voteAnnouncement } from "app/frontend/components/bill/voteAnnouncement";
import { Button } from "app/frontend/components/ui/button";
import { Support } from "app/frontend/sway_constants";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { sway } from "sway";

import "app/frontend/components/bill/cornerstore-vote-panel.css";

interface IProps {
    bill: sway.IBill;
    user_vote?: sway.IUserVote | null;
}

interface IBlockProps {
    support: sway.TUserSupport;
    label: string;
    sublabel: string;
    tone: "for" | "against";
    cast: boolean;
    disabled: boolean;
    onChoose: (support: sway.TUserSupport) => void;
}

const PosterBlock: React.FC<IBlockProps> = ({ support, label, sublabel, tone, cast, disabled, onChoose }) => (
    <button
        type="button"
        className={`cs-block cs-block--${tone}`}
        aria-pressed={cast}
        disabled={disabled}
        onClick={() => onChoose(support)}
    >
        <span className="cs-block__word">{label}</span>
        <span className="cs-block__sub">{sublabel}</span>
        {cast && <span className="cs-block__mark">Recorded ✓</span>}
    </button>
);

// @lat: [[user-vote-submission#Themed web vote controls]]
const CornerstoreVotePanel: React.FC<IProps> = ({ bill, user_vote }) => {
    const {
        voteRecorded,
        disabled,
        processing,
        pendingSupport,
        provisionalSupport,
        isAuthModalOpen,
        setIsAuthModalOpen,
        offlineMessageVisible,
        handleChoice,
    } = useCastUserVote(bill, user_vote);

    return (
        <section className="cs-panel" aria-labelledby="cs-vote-heading">
            <h2 id="cs-vote-heading" className="cs-panel__title">
                {PARITY_COPY.votePanel.title}
            </h2>

            <div className="cs-blocks" data-testid={voteRecorded ? "vote-recorded" : undefined}>
                <PosterBlock
                    support={Support.For as sway.TUserSupport}
                    label={PARITY_COPY.votePanel.forLabel}
                    sublabel={PARITY_COPY.votePanel.forSublabel}
                    tone="for"
                    cast={voteRecorded === Support.For}
                    disabled={disabled}
                    onChoose={handleChoice}
                />
                <PosterBlock
                    support={Support.Against as sway.TUserSupport}
                    label={PARITY_COPY.votePanel.againstLabel}
                    sublabel={PARITY_COPY.votePanel.againstSublabel}
                    tone="against"
                    cast={voteRecorded === Support.Against}
                    disabled={disabled}
                    onChoose={handleChoice}
                />
            </div>

            {/* @lat: [[vote-panel-announcements#What a screen reader hears when a vote is cast]] */}
            <output data-testid="vote-announcement" className="sr-only">
                {voteAnnouncement({ voteRecorded, pendingSupport, processing })}
            </output>

            {/* @lat: [[low-friction-voting#Provisional vote capture and cookie lifecycle]] */}
            {provisionalSupport && !voteRecorded && (
                <div
                    data-testid="provisional-vote-banner"
                    className="rounded-xl border border-amber-500/40 bg-amber-50/80 p-4 dark:bg-amber-950/20 space-y-2"
                >
                    <div className="flex items-start gap-3">
                        <CheckCircle2 className="size-5 text-amber-600 dark:text-amber-400 shrink-0 mt-0.5" />
                        <div className="space-y-1">
                            <h3 className="text-sm font-bold text-foreground">
                                Your vote is saved! Complete quick registration to make your voice count with your
                                representative.
                            </h3>
                            <p className="text-xs text-muted-foreground italic">
                                Pending constituent verification — not yet included in official tallies.
                            </p>
                        </div>
                    </div>
                    <div className="pl-8 pt-1">
                        <Button
                            type="button"
                            size="sm"
                            className="bg-amber-600 hover:bg-amber-700 text-white font-bold"
                            onClick={() => setIsAuthModalOpen(true)}
                        >
                            Complete registration
                        </Button>
                    </div>
                </div>
            )}

            {voteRecorded && (
                <p className="cs-receipt">{PARITY_COPY.votePanel.recordedVote(voteRecorded as "FOR" | "AGAINST")}</p>
            )}

            {pendingSupport && processing && (
                <p className="cs-pending">
                    <img src="/images/loading.svg" alt="" className="cs-spinner" aria-hidden="true" />
                    {PARITY_COPY.vote.processing(pendingSupport as "FOR" | "AGAINST")}
                </p>
            )}

            {offlineMessageVisible && (
                <p role="alert" aria-live="assertive" className="cs-offline">
                    {PARITY_COPY.vote.offlineMessage}
                </p>
            )}

            <ProvisionalRegistrationModal
                bill={bill}
                provisionalSupport={provisionalSupport}
                open={isAuthModalOpen}
                onOpenChange={setIsAuthModalOpen}
            />
        </section>
    );
};

export default CornerstoreVotePanel;
