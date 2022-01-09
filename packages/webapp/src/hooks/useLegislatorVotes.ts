import { useCallback, useState } from "react";
import { sway } from "sway";
import { useLocale, useUser } from ".";
import { handleError, swayFireClient } from "../utils";

export const useLegislatorVotes = (): [
    sway.ILegislatorBillSupport,
    (externalLegislatorIds: string[], billFirestoreId: string) => void,
] => {
    const user = useUser();
    const [locale] = useLocale(user);
    const [votes, setVotes] = useState<sway.ILegislatorBillSupport>(
        {} as sway.ILegislatorBillSupport,
    );

    const get = useCallback(
        (externalLegislatorIds: string[], billFirestoreId: string) => {
            const promises = externalLegislatorIds.map((id) =>
                swayFireClient(locale)
                    .legislatorVotes()
                    .get(id, billFirestoreId),
            );
            Promise.all(promises)
                .then((_votes) => {
                    setVotes(
                        _votes.reduce((sum, v) => {
                            if (
                                v &&
                                v.externalLegislatorId &&
                                v.billFirestoreId === billFirestoreId
                            ) {
                                sum[v.externalLegislatorId] = v.support;
                            }
                            return sum;
                        }, {}),
                    );
                })
                .catch(handleError);
        },
        [locale],
    );

    return [votes, get];
};
