import { logDev } from "@sway/utils";
import { useState, useCallback } from "react";
import { sway } from "sway";
import { handleError } from "../../utils";
import { useCancellable } from "../useCancellable";
import { useSwayFireClient } from "../useSwayFireClient";
import { useUser } from "../useUsers";

export const useBill = (
    billFirestoreId: string,
): [sway.IBillOrgsUserVoteScore, () => void, boolean] => {
    const makeCancellable = useCancellable();
    const fire = useSwayFireClient();
    const { uid } = useUser();
    const [selectedBill, setSelectedBill] = useState<sway.IBillOrgsUserVoteScore>({
        bill: { firestoreId: billFirestoreId },
        userVote: undefined,
    } as sway.IBillOrgsUserVoteScore);
    const [isLoading, setLoading] = useState<boolean>(false);

    const getBill = useCallback(() => {
        const withUserVote = (bill: sway.IBill | undefined | void) => {
            if (!bill || !uid) return;
            return fire.userVotes(uid).get(bill.firestoreId);
        };

        const withOrganizations = (bill: sway.IBill | undefined | void) => {
            if (!bill) return;
            return fire.organizations().listPositions(bill.firestoreId);
        };

        const withScore = async (
            bill: sway.IBill | undefined | void,
        ): Promise<sway.IBillScore | undefined> => {
            if (!bill) return;
            return fire.billScores().get(bill.firestoreId);
        };

        const withOrgsAndUserVoteAndScore = (bill: sway.IBill | undefined | void) => {
            return makeCancellable(
                Promise.all([withOrganizations(bill), withUserVote(bill), withScore(bill)]),
                () => {
                    logDev("Canceled getBill withOrgsAndUserVoteAndScore");
                },
            )
                .then(([organizations, userVote, score]) => {
                    if (!bill) return;

                    setSelectedBill({
                        bill,
                        organizations,
                        userVote,
                        score,
                    });
                })
                .catch(handleError);
        };

        const handleGetBill = (): Promise<sway.IBill | undefined | void> => {
            return new Promise((resolve) => {
                setLoading(true);
                resolve(true);
            })
                .then(() => fire.bills().get(billFirestoreId))
                .catch(console.error);
        };

        makeCancellable(handleGetBill(), () => {
            logDev("Cancelled useBill getBill");
        })
            .then((result) => {
                setLoading(false);
                withOrgsAndUserVoteAndScore(result).catch(handleError);
            })
            .catch((error) => {
                setLoading(false);
                handleError(error);
            });
    }, [fire, uid, billFirestoreId, setSelectedBill, setLoading, makeCancellable]);

    return [selectedBill, getBill, isLoading];
};
