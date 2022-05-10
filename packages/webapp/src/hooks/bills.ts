import { logDev } from "@sway/utils";
import { useCallback, useState } from "react";
import { sway } from "sway";
import { handleError, swayFireClient } from "../utils";
import { useCancellable } from "./cancellable";

export const useBillOfTheWeek = (): [
    sway.IBillOrgsUserVoteScore | undefined,
    (locale: sway.ILocale, uid: string | null) => void,
    boolean,
] => {
    const makeCancellable = useCancellable();

    const [botw, setBotw] = useState<sway.IBillOrgsUserVoteScore | undefined>();
    const [isLoading, setLoading] = useState<boolean>(false);

    const getBotw = useCallback(
        (locale: sway.ILocale, uid: string | null) => {
            if (!locale) return;

            const withUserVote = (bill: sway.IBill | undefined | void) => {
                if (!bill || !uid) return;
                return swayFireClient(locale).userVotes(uid).get(bill.firestoreId);
            };

            const withOrganizations = (bill: sway.IBill | undefined | void) => {
                if (!bill) return;
                return swayFireClient(locale).organizations().listPositions(bill.firestoreId);
            };

            const withScore = async (
                bill: sway.IBill | undefined | void,
            ): Promise<sway.IBillScore | undefined> => {
                if (!bill) return;
                return swayFireClient(locale).billScores().get(bill.firestoreId);
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
                    .then(() => swayFireClient(locale).bills().ofTheWeek())
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
        },
        [setBotw, setLoading],
    );

    return [botw, getBotw, isLoading];
};

export const useBill = (
    billFirestoreId: string,
): [
    sway.IBillOrgsUserVoteScore | undefined,
    (locale: sway.ILocale, uid: string | null | undefined) => void,
    boolean,
] => {
    const makeCancellable = useCancellable();

    const [selectedBill, setSelectedBill] = useState<sway.IBillOrgsUserVoteScore | undefined>();
    const [isLoading, setLoading] = useState<boolean>(false);

    const getBill = useCallback(
        (locale: sway.ILocale, uid: string | null | undefined) => {
            if (!locale) return;

            const withUserVote = (bill: sway.IBill | undefined | void) => {
                if (!bill || !uid) return;
                return swayFireClient(locale).userVotes(uid).get(bill.firestoreId);
            };

            const withOrganizations = (bill: sway.IBill | undefined | void) => {
                if (!bill) return;
                return swayFireClient(locale).organizations().listPositions(bill.firestoreId);
            };

            const withScore = async (
                bill: sway.IBill | undefined | void,
            ): Promise<sway.IBillScore | undefined> => {
                if (!bill) return;
                return swayFireClient(locale).billScores().get(bill.firestoreId);
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
                    .then(() => swayFireClient(locale).bills().get(billFirestoreId))
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
        },
        [billFirestoreId, setSelectedBill, setLoading],
    );

    return [selectedBill, getBill, isLoading];
};

export const useBills = (): [
    sway.IBillOrgsUserVoteScore[],
    (_locale: sway.ILocale, _uid: string | null, _categories: string[]) => Promise<void>,
    boolean,
] => {
    const makeCancellable = useCancellable();

    const [isLoading, setLoading] = useState<boolean>(false);
    const [bills, setBills] = useState<sway.IBillOrgsUserVoteScore[]>([]);

    const getBills = useCallback(
        async (locale: sway.ILocale, uid: string | null, categories: string[]) => {
            if (!locale) return;

            const withUserVote = (bill: sway.IBill | undefined | void) => {
                if (!bill || !uid) return;
                return swayFireClient(locale).userVotes(uid).get(bill.firestoreId);
            };

            const withOrganizations = (bill: sway.IBill | undefined | void) => {
                if (!bill) return;
                return swayFireClient(locale).organizations().listPositions(bill.firestoreId);
            };

            const withScore = async (
                bill: sway.IBill | undefined | void,
            ): Promise<sway.IBillScore | undefined> => {
                if (!bill) return;
                return swayFireClient(locale).billScores().get(bill.firestoreId);
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
                    .then(() => swayFireClient(locale).bills().list(categories))
                    .catch(handleError);
            };

            makeCancellable(handleGetBill(), () => {
                logDev("Cancelled useBills getBills");
            })
                .then(withOrgsAndUserVoteAndScore)
                .then((result) => {
                    setLoading(false);
                    setBills(result);
                })
                .catch((error) => {
                    setLoading(false);
                    handleError(error);
                });
        },
        [setBills, setLoading],
    );

    return [bills, getBills, isLoading];
};
