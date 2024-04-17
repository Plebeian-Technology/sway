import { logDev } from "app/frontend/sway_utils";
import { useCallback, useState } from "react";
import { sway } from "sway";
import { handleError } from "../sway_utils";
import { useCancellable } from "./useCancellable";
import { useUser } from "./users/useUser";
import { useSwayFireClient } from "./useSwayFireClient";

export const useBillOfTheWeek = (): [
    sway.IBillOrgsUserVoteScore | undefined,
    () => void,
    boolean,
] => {
    const makeCancellable = useCancellable();
    const fire = useSwayFireClient();
    const { uid } = useUser();
    const [botw, setBotw] = useState<sway.IBillOrgsUserVoteScore | undefined>();
    const [isLoading, setLoading] = useState<boolean>(false);

    const getBotw = useCallback(() => {
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
                    logDev("Canceled getBOTW withOrgsAndUserVoteAndScore");
                },
            )
                .then(([organizations, userVote, score]) => {
                    setLoading(false);
                    if (bill) {
                        setBotw({
                            bill,
                            organizations,
                            userVote,
                            score,
                        });
                    }
                })
                .catch(handleError);
        };

        const handleGetBill = (): Promise<sway.IBill | undefined | void> => {
            return new Promise((resolve) => {
                setLoading(true);
                resolve(true);
            })
                .then(() => fire.bills().ofTheWeek())
                .catch(handleError);
        };

        makeCancellable(handleGetBill(), () => {
            logDev("Cancelled useBillOfTheWeek getBill");
        })
            .then((result) => withOrgsAndUserVoteAndScore(result).catch(handleError))
            .catch((error) => {
                setLoading(false);
                handleError(error);
            });
    }, [fire, uid, setBotw, setLoading, makeCancellable]);

    return [botw, getBotw, isLoading];
};
