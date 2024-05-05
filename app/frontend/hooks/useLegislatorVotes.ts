import { useCallback, useMemo, useState } from "react";
import { sway } from "sway";
import { handleError, swayFireClient } from "../sway_utils";
import { useLocale } from "./useLocales";

export const useLegislatorVotes = (): [
    sway.ILegislatorBillSupport,
    string[],
    (externalLegislatorIds: string[], billExternalId: string) => Promise<void>,
] => {
    const [locale] = useLocale();
    const [votes, setVotes] = useState<sway.ILegislatorBillSupport>(
        {} as sway.ILegislatorBillSupport,
    );

    const get = useCallback(
        async (externalLegislatorIds: string[], billExternalId: string) => {
            const promises = externalLegislatorIds.map((id) =>
                swayFireClient(locale).legislatorVotes().get(id, billExternalId),
            );
            Promise.all(promises)
                .then((newVotes) => {
                    setVotes(
                        newVotes.reduce((sum, v) => {
                            if (
                                v &&
                                v.externalLegislatorId &&
                                v.billExternalId === billExternalId
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

    const voteIds = useMemo(() => Object.keys(votes), [votes]);
    return [votes, voteIds, get];
};
