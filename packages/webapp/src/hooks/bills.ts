import { useCallback, useState } from "react";
import { sway } from "sway";
import { handleError, swayFireClient } from "../utils";

export const useBillOfTheWeek = (): [
    sway.IBillOrgsUserVote | undefined,
    (locale: sway.ILocale, uid: string | null) => void,
    boolean,
] => {
    const [botw, setBotw] = useState<sway.IBillOrgsUserVote | undefined>();
    const [isLoading, setIsLoading] = useState<boolean>(false);

    const getBotw = useCallback(
        (locale: sway.ILocale, uid: string | null) => {
            if (!locale) return;

            const withUserVote = (bill: sway.IBill | undefined) => {
                if (!bill || !uid) return;
                return swayFireClient(locale).userVotes(uid).get(bill.firestoreId);
            };

            const withOrganizations = (bill: sway.IBill | undefined) => {
                if (!bill) return;
                return swayFireClient(locale)
                    .organizations()
                    .listPositions(bill.firestoreId);
            };

            const withOrgsAndUserVote = (bill: sway.IBill | undefined) => {
                return Promise.all([
                    withOrganizations(bill),
                    withUserVote(bill),
                ])
                    .then(([organizations, userVote]) => {
                        if (!bill) return;

                        setBotw({
                            bill,
                            organizations,
                            userVote,
                        });
                    })
                    .catch(handleError);
            };

            setIsLoading(true);
            swayFireClient(locale)
                .bills()
                .ofTheWeek()
                .then(withOrgsAndUserVote)
                .catch(handleError)
                .finally(() => setIsLoading(false));
        },
        [setBotw, setIsLoading],
    );

    return [botw, getBotw, isLoading];
};

export const useBill = (billFirestoreId: string): [
    sway.IBillOrgsUserVote | undefined,
    (locale: sway.ILocale, uid: string | null | undefined) => void,
    boolean,
] => {
    const [selectedBill, setSelectedBill] = useState<sway.IBillOrgsUserVote | undefined>();
    const [isLoading, setIsLoading] = useState<boolean>(false);

    const getBill = useCallback(
        (locale: sway.ILocale, uid: string | null | undefined) => {
            if (!locale) return;

            const withUserVote = (bill: sway.IBill | undefined) => {
                if (!bill || !uid) return;
                return swayFireClient(locale).userVotes(uid).get(bill.firestoreId);
            };

            const withOrganizations = (bill: sway.IBill | undefined) => {
                if (!bill) return;
                return swayFireClient(locale)
                    .organizations()
                    .listPositions(bill.firestoreId);
            };

            const withOrgsAndUserVote = (bill: sway.IBill | undefined) => {
                return Promise.all([
                    withOrganizations(bill),
                    withUserVote(bill),
                ])
                    .then(([organizations, userVote]) => {
                        if (!bill) return;

                        setSelectedBill({
                            bill,
                            organizations,
                            userVote,
                        });
                    })
                    .catch(handleError);
            };

            setIsLoading(true);
            swayFireClient(locale)
                .bills()
                .get(billFirestoreId)
                .then(withOrgsAndUserVote)
                .catch(handleError)
                .finally(() => setIsLoading(false));
        },
        [billFirestoreId, setSelectedBill, setIsLoading],
    );

    return [selectedBill, getBill, isLoading];
};

export const useBills = (): [
    sway.IBillOrgsUserVote[],
    (_locale: sway.ILocale, _uid: string | null, _categories: string[]) => void,
    boolean,
] => {
    const [isLoading, setIsLoading] = useState<boolean>(false);
    const [bills, setBills] = useState<sway.IBillOrgsUserVote[]>([]);

    const getBills = useCallback(
        (locale: sway.ILocale, uid: string | null, categories: string[]) => {
            if (!locale) return;

            const withUserVote = (bill: sway.IBill | undefined) => {
                if (!bill || !uid) return;
                return swayFireClient(locale).userVotes(uid).get(bill.firestoreId);
            };

            const withOrganizations = (bill: sway.IBill | undefined) => {
                if (!bill) return;
                return swayFireClient(locale)
                    .organizations()
                    .listPositions(bill.firestoreId);
            };

            const withOrgsAndUserVote = async (
                _bills: sway.IBill[] | undefined,
            ): Promise<sway.IBillOrgsUserVote[]> => {
                if (!_bills) return [] as sway.IBillOrgsUserVote[];

                return Promise.all(
                    _bills.filter(Boolean).map((bill: sway.IBill) => {
                        return Promise.all([
                            withOrganizations(bill),
                            withUserVote(bill),
                        ])
                            .then(([organizations, userVote]) => ({
                                bill,
                                organizations,
                                userVote,
                            }))
                            .catch((error) => {
                                handleError(error);
                                return { bill };
                            });
                    }),
                );
            };

            setIsLoading(true);
            swayFireClient(locale)
                .bills()
                .list(categories)
                .then(withOrgsAndUserVote)
                .then(setBills)
                .catch(handleError)
                .finally(() => setIsLoading(false));
        },
        [setBills, setIsLoading],
    );

    return [bills, getBills, isLoading];
};
