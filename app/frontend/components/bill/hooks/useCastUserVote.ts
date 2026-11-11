import { router, useForm, usePage } from "@inertiajs/react";
import { useCallback, useMemo, useState } from "react";

import { isArchivedHistoricalBill } from "app/frontend/components/bill/sway_utils/billArchiving";
import { useOffline } from "app/frontend/components/contexts/hooks/useOffline";
import { useConfirm } from "app/frontend/components/ui/confirm-dialog";
import { handleError, notify, withTadas } from "app/frontend/sway_utils";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { trackFunnelStep } from "app/frontend/sway_utils/funnelTracker";
import { sway } from "sway";

export interface CastUserVoteState {
    voteRecorded?: sway.TUserSupport;
    disabled: boolean;
    processing: boolean;
    pendingSupport: sway.TUserSupport | null;
    provisionalSupport?: sway.TUserSupport | null;
    isAuthModalOpen: boolean;
    setIsAuthModalOpen: (open: boolean) => void;
    offlineMessageVisible: boolean;
    handleChoice: (support: sway.TUserSupport) => void;
}

// @lat: [[user-vote-submission#Submission hooks]]
export function useCastUserVote(bill: sway.IBill, user_vote?: sway.IUserVote | null): CastUserVoteState {
    const pageProps = usePage<sway.IPageProps>().props;
    const user = pageProps.user;
    const pendingVoteCookie = pageProps.pending_vote;

    const [pendingSupport, setPendingSupport] = useState<sway.TUserSupport | null>(null);
    const [provisionalSupport, setProvisionalSupport] = useState<sway.TUserSupport | null>(() => {
        if (!user && pendingVoteCookie && pendingVoteCookie.bill_id === bill.id) {
            return pendingVoteCookie.support;
        }
        return null;
    });
    const [isAuthModalOpen, setIsAuthModalOpen] = useState<boolean>(false);
    const [offlineMessageVisible, setOfflineMessageVisible] = useState(false);
    const { isOnline, assertBanner } = useOffline();
    const confirm = useConfirm();

    const defaultValues = useMemo(
        () => ({
            bill_id: bill.id,
            support: user_vote?.support,
            redirect_to: globalThis.location.pathname,
        }),
        [bill.id, user_vote?.support],
    );

    const { data, setData, post, processing, transform } = useForm<
        { bill_id: number; redirect_to: string } & Pick<sway.IUserVote, "support">
    >(defaultValues);

    const setSupport = useCallback((support: sway.TUserSupport | undefined) => setData("support", support), [setData]);

    const createVote = useCallback(
        async (support: sway.TUserSupport) => {
            if (!isOnline) {
                setOfflineMessageVisible(true);
                assertBanner();
                return;
            }

            setOfflineMessageVisible(false);
            setSupport(support);
            // @lat: [[user-vote-submission#Submission hooks]]
            transform((current) => ({ ...current, support }));
            post("/user_votes", {
                preserveScroll: true,
                onSuccess: () => {
                    const isFirstVote = !user_vote?.support;
                    if (isFirstVote) {
                        trackFunnelStep("first_vote_cast", {
                            bill_id: bill.id,
                            bill_external_id: bill.external_id,
                            support,
                        });
                    }
                    notify({
                        level: "success",
                        title: `Vote on bill ${bill.external_id} cast!`,
                        message: withTadas("You gained some Sway!"),
                    });
                    setPendingSupport(null);
                },
                onError: () => {
                    // @lat: [[user-vote-submission#Submission hooks]]
                    setSupport(user_vote?.support);
                    notify({ level: "error", title: "Error saving vote.", message: "Please try again." });
                    setPendingSupport(null);
                },
            });
        },
        [assertBanner, bill.external_id, bill.id, isOnline, post, setSupport, transform, user_vote?.support],
    );

    // @lat: [[low-friction-voting#Provisional vote capture and cookie lifecycle]]
    const createProvisionalVote = useCallback(
        async (support: sway.TUserSupport) => {
            if (!isOnline) {
                setOfflineMessageVisible(true);
                assertBanner();
                return;
            }

            const previousProvisionalSupport = provisionalSupport;
            setOfflineMessageVisible(false);
            setPendingSupport(support);
            setProvisionalSupport(support);

            try {
                const csrfToken = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || "";
                const resp = await fetch("/provisional_votes", {
                    method: "POST",
                    headers: {
                        "Content-Type": "application/json",
                        Accept: "application/json",
                        "X-CSRF-Token": csrfToken,
                    },
                    credentials: "same-origin",
                    body: JSON.stringify({ bill_id: bill.id, support }),
                });

                setPendingSupport(null);

                if (resp.ok) {
                    router.flushAll?.();
                    setIsAuthModalOpen(true);
                } else {
                    setProvisionalSupport(previousProvisionalSupport);
                    notify({ level: "error", title: "Error saving provisional vote.", message: "Please try again." });
                }
            } catch (e) {
                setPendingSupport(null);
                setProvisionalSupport(previousProvisionalSupport);
                console.error("Provisional vote error:", e);
                notify({ level: "error", title: "Error saving provisional vote.", message: "Please try again." });
            }
        },
        [assertBanner, bill.id, isOnline, provisionalSupport],
    );

    const handleChoice = useCallback(
        (support: sway.TUserSupport) => {
            if (!user) {
                // @lat: [[low-friction-voting#Provisional vote capture and cookie lifecycle]]
                createProvisionalVote(support).catch(handleError);
                return;
            }

            const run = async () => {
                const confirmed = await confirm({
                    title: PARITY_COPY.vote.confirmTitle,
                    description: PARITY_COPY.vote.confirmMessage(support as "FOR" | "AGAINST", bill.external_id),
                    confirmLabel: PARITY_COPY.vote.confirmConfirm,
                    cancelLabel: PARITY_COPY.vote.confirmCancel,
                    tone: "destructive",
                });

                if (!confirmed) {
                    return;
                }

                setPendingSupport(support);
                await createVote(support);
            };

            run().catch(handleError);
        },
        [bill.external_id, confirm, createProvisionalVote, createVote, user],
    );

    const voteRecorded = data.support ?? user_vote?.support;
    const isBillVotable = !isArchivedHistoricalBill(bill) && (bill.active !== false || Boolean(user));

    return {
        voteRecorded,
        disabled: processing || Boolean(voteRecorded) || !isBillVotable,
        processing,
        pendingSupport,
        provisionalSupport,
        isAuthModalOpen,
        setIsAuthModalOpen,
        offlineMessageVisible,
        handleChoice,
    };
}
