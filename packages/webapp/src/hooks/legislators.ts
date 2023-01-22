/** @format */

import { isEmptyObject, logDev, removeTimestamps, toFormattedLocaleName } from "@sway/utils";
import { useCallback, useState } from "react";
import { sway } from "sway";
import { handleError, swayFireClient } from "../utils";
import { useCancellable } from "./cancellable";

interface IActiveRepresentatives {
    representatives: sway.ILegislator[];
    isActive: boolean;
}

export const useHookedRepresentatives = (): [
    IActiveRepresentatives | undefined,
    (
        user: sway.IUser | undefined,
        locale: sway.IUserLocale,
        active: boolean,
    ) => Promise<IActiveRepresentatives | undefined | void>,
    boolean,
] => {
    const makeCancellable = useCancellable();

    const [reps, setReps] = useState<IActiveRepresentatives | undefined>();
    const [isLoading, setLoading] = useState<boolean>(false);

    const withoutTimestamps = (legislator: sway.ILegislator) => {
        return removeTimestamps(legislator);
    };

    const getRepresentatives = useCallback(
        async (user: sway.IUser | undefined, locale: sway.IUserLocale, isActive: boolean) => {
            logDev("getRepresentatives");
            if (!user?.locales) {
                logDev("getRepresentatives - no user locales or no district -", locale);
                console.error(
                    new Error("getRepresentatives: no user locales or no locale district"),
                    `No legislators found in ${toFormattedLocaleName(locale.name)}`,
                );
            }

            logDev("getRepresentatives - getting representatives for user locale -", locale);

            const handleGetLegislators = async (): Promise<
                sway.ILegislator[] | undefined | void
            > => {
                if (locale.district || locale.regionCode || user?.regionCode) {
                    return swayFireClient(locale)
                        .legislators()
                        .representatives(
                            locale.district.replace(user?.regionCode || "", ""),
                            user?.regionCode || locale.regionCode,
                            isActive,
                            // locale?.district || `${locale.regionCode}0`,
                            // user?.regionCode || locale.regionCode,
                            // isActive,
                        )
                        .catch(handleError);
                }
            };

            setLoading(true);
            return makeCancellable(handleGetLegislators(), () => {
                logDev(
                    "getRepresentatives - Cancelled useHookedRepresentatives getRepresentatives",
                );
            })
                .then((legislators) => {
                    setLoading(false);
                    logDev("getRepresentatives - handled", legislators);
                    if (!legislators || isEmptyObject(legislators)) {
                        handleError(
                            new Error(
                                `getRepresentatives: received no legislators for locale - ${locale.name}.`,
                            ),
                            `No legislators found in ${toFormattedLocaleName(locale.name)}`,
                        );
                        return;
                    }

                    const _reps = {
                        representatives: legislators.map(withoutTimestamps),
                        isActive,
                    };
                    setReps(_reps);
                    return _reps;
                })
                .catch((error) => {
                    setLoading(false);
                    handleError(error);
                });
        },
        [setReps, setLoading],
    );

    return [reps, getRepresentatives, isLoading];
};
