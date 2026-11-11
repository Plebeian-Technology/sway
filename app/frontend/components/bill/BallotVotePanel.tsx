import { CheckCircle2 } from "lucide-react";

import { useCastUserVote } from "app/frontend/components/bill/hooks/useCastUserVote";
import ProvisionalRegistrationModal from "app/frontend/components/bill/ProvisionalRegistrationModal";
import { voteAnnouncement } from "app/frontend/components/bill/voteAnnouncement";
import { Button } from "app/frontend/components/ui/button";
import { Support } from "app/frontend/sway_constants";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { sway } from "sway";

import "app/frontend/components/bill/ballot-vote-panel.css";

interface IProps {
    bill: sway.IBill;
    user_vote?: sway.IUserVote | null;
}

interface IRowProps {
    support: sway.TUserSupport;
    label: string;
    sublabel: string;
    cast: boolean;
    disabled: boolean;
    onChoose: (support: sway.TUserSupport) => void;
}

const BallotRow: React.FC<IRowProps> = ({ support, label, sublabel, cast, disabled, onChoose }) => (
    <button type="button" className="bal-row" aria-pressed={cast} disabled={disabled} onClick={() => onChoose(support)}>
        <span className="bal-oval" aria-hidden="true" />
        <span className="bal-choice">
            <span className="bal-word">{label}</span>
            <span className="bal-sub">{sublabel}</span>
        </span>
        {/* @lat: [[theme-driven-bill-layout-selection#Why BallotVotePanel.tsx is drawn as a real ballot]] */}
        {cast && <span className="bal-stamp">Recorded ✓</span>}
    </button>
);

// @lat: [[user-vote-submission#Themed web vote controls]]
const BallotVotePanel: React.FC<IProps> = ({ bill, user_vote }) => {
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
        <section className="bal-panel" aria-labelledby="bal-vote-heading">
            <div className="bal-head">
                <h2 id="bal-vote-heading" className="bal-title">
                    {PARITY_COPY.votePanel.title}
                </h2>
                <p className="bal-instruction">Fill the oval completely, as you would on your ballot.</p>
            </div>

            <div className="bal-rows" data-testid={voteRecorded ? "vote-recorded" : undefined}>
                <BallotRow
                    support={Support.For as sway.TUserSupport}
                    label={PARITY_COPY.votePanel.forLabel}
                    sublabel={PARITY_COPY.votePanel.forSublabel}
                    cast={voteRecorded === Support.For}
                    disabled={disabled}
                    onChoose={handleChoice}
                />
                <BallotRow
                    support={Support.Against as sway.TUserSupport}
                    label={PARITY_COPY.votePanel.againstLabel}
                    sublabel={PARITY_COPY.votePanel.againstSublabel}
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
                <p className="bal-receipt">{PARITY_COPY.votePanel.recordedVote(voteRecorded as "FOR" | "AGAINST")}</p>
            )}

            {pendingSupport && processing && (
                <p className="bal-pending">
                    <img src="/images/loading.svg" alt="" className="bal-spinner" aria-hidden="true" />
                    {PARITY_COPY.vote.processing(pendingSupport as "FOR" | "AGAINST")}
                </p>
            )}

            {offlineMessageVisible && (
                <p role="alert" aria-live="assertive" className="bal-offline">
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

export default BallotVotePanel;
