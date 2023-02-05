import { logDev } from "@sway/utils";
import { useCallback, useState } from "react";
import { sway } from "sway";
import { handleError } from "../utils";
import { useCancellable } from "./cancellable";
import { useUser } from "./users";
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
