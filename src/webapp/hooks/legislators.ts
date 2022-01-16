/** @format */

import { isEmptyObject, logDev, removeTimestamps } from "src/utils";
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
    const [isLoading, setIsLoading] = useState<boolean>(false);

    const withoutTimestamps = (legislator: sway.ILegislator) => {
        return removeTimestamps(legislator);
    };

    const getRepresentatives = useCallback(
        async (
            user: sway.IUser | undefined,
            locale: sway.IUserLocale,
            isActive: boolean,
        ) => {
            logDev("getRepresentatives");
            if (!user?.locales || !locale?.district) {
                logDev(
                    "getRepresentatives - no user locales or no district -",
                    locale,
                );
                handleError(
                    new Error(
                        "getRepresentatives: no user locales or no locale district",
                    ),
                    "Failed getting district.",
                );
                return;
            }

            logDev(
                "getRepresentatives - getting representatives for user locale -",
                locale,
            );

            const handleGetLegislators = async (): Promise<
                sway.ILegislator[] | undefined | void
            > => {
                return swayFireClient(locale)
                    .legislators()
                    .representatives(locale.district, user.regionCode, isActive)
                    .catch(handleError);
            };

            return makeCancellable(handleGetLegislators(), () => {
                logDev(
                    "getRepresentatives - Cancelled useHookedRepresentatives getRepresentatives",
                );
            })
                .then((legislators) => {
                    logDev("getRepresentatives - handled");
                    if (!legislators || isEmptyObject(legislators)) {
                        handleError(
                            new Error(
                                `getRepresentatives: received no legislators for locale - ${locale.name}.`,
                            ),
                            "Legislators empty for locale.",
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
                .catch(handleError)
                .finally(() => setIsLoading(false));
        },
        [setReps, setIsLoading],
    );

    return [reps, getRepresentatives, isLoading];
};
