import { useId } from "react";
import { CheckCircle2 } from "lucide-react";

import { useCastUserVote } from "app/frontend/components/bill/hooks/useCastUserVote";
import ProvisionalRegistrationModal from "app/frontend/components/bill/ProvisionalRegistrationModal";
import { voteAnnouncement } from "app/frontend/components/bill/voteAnnouncement";
import { cn } from "app/frontend/lib/utils";
import { Support } from "app/frontend/sway_constants";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { Button } from "app/frontend/components/ui/button";
import { sway } from "sway";

interface IProps {
    bill: sway.IBill;
    user_vote?: sway.IUserVote | null;
    className?: string;
}

// @lat: [[user-vote-submission#Themed web vote controls]]
const FOR_BUTTON_CLASSES = {
    idle: "border-vote-for bg-transparent text-foreground ring-transparent hover:bg-vote-for hover:text-white",
    cast: "border-vote-for bg-vote-for text-success-foreground ring-transparent",
};
const AGAINST_BUTTON_CLASSES = {
    idle: "border-vote-against bg-transparent text-foreground ring-transparent hover:bg-vote-against hover:text-white",
    cast: "border-vote-against bg-vote-against text-white ring-transparent",
};

// @lat: [[low-friction-voting#Provisional vote capture and cookie lifecycle]]
const PROVISIONAL_BUTTON_CLASSES = {
    selected: "border-amber-500 bg-amber-500/20 text-foreground ring-amber-500 hover:bg-amber-500/30",
};

const CHOICE_BUTTON_CLASSES = "h-auto min-w-0 justify-start whitespace-normal px-4 py-4 text-left sm:px-6 sm:py-5";

// @lat: [[user-vote-submission#Themed web vote controls#Where the default control sits]]
const VotePanel: React.FC<IProps> = ({ bill, user_vote, className }) => {
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
    const titleId = useId();

    return (
        <section data-testid="bill-ballot" aria-labelledby={titleId} className={cn("space-y-4", className)}>
            <h2 id={titleId} className="text-xl font-black leading-none">
                {PARITY_COPY.votePanel.title}
            </h2>

            <div
                data-testid={voteRecorded ? "vote-recorded" : undefined}
                className="grid grid-cols-[repeat(auto-fit,minmax(min(100%,8rem),1fr))] gap-3"
            >
                <Button
                    type="button"
                    variant="outline"
                    className={`${CHOICE_BUTTON_CLASSES} ${
                        voteRecorded === Support.For
                            ? FOR_BUTTON_CLASSES.cast
                            : !voteRecorded && provisionalSupport === Support.For
                              ? PROVISIONAL_BUTTON_CLASSES.selected
                              : FOR_BUTTON_CLASSES.idle
                    }`}
                    disabled={disabled}
                    onClick={() => handleChoice(Support.For as "FOR")}
                >
                    <span className="flex min-w-0 flex-col items-start gap-1">
                        <span className="text-lg font-black leading-none sm:text-2xl">
                            {PARITY_COPY.votePanel.forLabel}
                        </span>
                        <span className="text-sm font-medium opacity-80">{PARITY_COPY.votePanel.forSublabel}</span>
                    </span>
                </Button>

                <Button
                    type="button"
                    variant="outline"
                    className={`${CHOICE_BUTTON_CLASSES} ${
                        voteRecorded === Support.Against
                            ? AGAINST_BUTTON_CLASSES.cast
                            : !voteRecorded && provisionalSupport === Support.Against
                              ? PROVISIONAL_BUTTON_CLASSES.selected
                              : AGAINST_BUTTON_CLASSES.idle
                    }`}
                    disabled={disabled}
                    onClick={() => handleChoice(Support.Against as "AGAINST")}
                >
                    <span className="flex min-w-0 flex-col items-start gap-1">
                        <span className="text-lg font-black leading-none sm:text-2xl">
                            {PARITY_COPY.votePanel.againstLabel}
                        </span>
                        <span className="text-sm font-medium opacity-80">{PARITY_COPY.votePanel.againstSublabel}</span>
                    </span>
                </Button>
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
                <div
                    data-neo-surface="true"
                    className="rounded-xl bg-surface-2 px-4 py-3 text-sm font-semibold text-foreground"
                >
                    {PARITY_COPY.votePanel.recordedVote(voteRecorded as "FOR" | "AGAINST")}
                </div>
            )}

            {pendingSupport && processing && (
                <div className="flex items-center gap-3 rounded-xl border-neo border-border bg-card px-4 py-3 text-sm font-semibold text-muted-foreground shadow-neo">
                    <img src="/images/loading.svg" alt="" className="size-5" aria-hidden="true" />
                    <span>{PARITY_COPY.vote.processing(pendingSupport as "FOR" | "AGAINST")}</span>
                </div>
            )}

            {offlineMessageVisible && (
                <div
                    role="alert"
                    aria-live="assertive"
                    className="rounded-xl border-neo border-primary bg-primary/10 px-4 py-3 text-sm font-semibold text-primary shadow-neo"
                >
                    {PARITY_COPY.vote.offlineMessage}
                </div>
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

export default VotePanel;
