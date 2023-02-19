import { logDev } from "@sway/utils";
import { useState, useCallback } from "react";
import { sway } from "sway";
import { handleError } from "../../utils";
import { useCancellable } from "../useCancellable";
import { useUser } from "../users/useUser";
import { useSwayFireClient } from "../useSwayFireClient";

// eslint-disable-next-line
export enum EUseBillsFilters {
    ORGANIZATIONS = "organizations",
    USER_VOTE = "user_vote",
    SCORE = "score",
}

export const useBills = (
    filters?: EUseBillsFilters[],
): [sway.IBillOrgsUserVoteScore[], (categories: string[]) => Promise<void>, boolean] => {
    const makeCancellable = useCancellable();
    const fire = useSwayFireClient();
    const { uid } = useUser();
    const [bills, setBills] = useState<sway.IBillOrgsUserVoteScore[]>([]);
    const [isLoading, setLoading] = useState<boolean>(false);

    const getBills = useCallback(
        async (categories: string[]) => {
            const withUserVote = (bill: sway.IBill | undefined | void) => {
                if (!bill || !uid) return;
                if (filters && !filters.includes(EUseBillsFilters.USER_VOTE)) return undefined;
                return fire.userVotes(uid).get(bill.firestoreId);
            };

            const withOrganizations = (bill: sway.IBill | undefined | void) => {
                if (!bill) return [];
                if (filters && !filters.includes(EUseBillsFilters.ORGANIZATIONS)) return [];
                return fire.organizations().listPositions(bill.firestoreId);
            };

            const withScore = async (
                bill: sway.IBill | undefined | void,
            ): Promise<sway.IBillScore | undefined> => {
                if (!bill) return;
                if (filters && !filters.includes(EUseBillsFilters.SCORE)) return undefined;
                return fire.billScores().get(bill.firestoreId);
            };

            const withOrgsAndUserVoteAndScore = async (
                _bills: sway.IBill[] | undefined | void,
            ): Promise<sway.IBillOrgsUserVoteScore[]> => {
                if (!_bills) return [] as sway.IBillOrgsUserVoteScore[];

                return makeCancellable(
                    Promise.all(
                        _bills.filter(Boolean).map((bill: sway.IBill) => {
                            return makeCancellable(
                                Promise.all([
                                    withOrganizations(bill),
                                    withUserVote(bill),
                                    withScore(bill),
                                ]),
                                () => {
                                    logDev("Canceled getBills withOrgsAndUserVoteAndScore");
                                },
                            )
                                .then(([organizations, userVote, score]) => ({
                                    bill,
                                    organizations,
                                    userVote,
                                    score,
                                }))
                                .catch((error) => {
                                    handleError(error);
                                    return { bill };
                                });
                        }),
                    ),
                    () => {
                        logDev("Canceled getBills MAPPING withOrgsAndUserVoteAndScore");
                    },
                );
            };

            const handleGetBill = (): Promise<sway.IBill[] | undefined | void> => {
                return new Promise((resolve) => {
                    setLoading(true);
                    resolve(true);
                })
                    .then(() => fire.bills().list(categories).catch(console.error))
                    .catch(handleError);
            };

            makeCancellable(handleGetBill(), () => {
                logDev("Cancelled useBills getBills");
            })
                .then(withOrgsAndUserVoteAndScore)
                .then((result) => {
                    logDev("handleGetBills.result - ", { result });
                    setLoading(false);
                    setBills(result);
                })
                .catch((error) => {
                    setLoading(false);
                    handleError(error);
                });
        },
        [fire, uid, filters, makeCancellable],
    );

    return [bills, getBills, isLoading];
};
