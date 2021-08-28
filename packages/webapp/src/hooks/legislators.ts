/** @format */

import { logDev, removeTimestamps } from "@sway/utils";
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
            if (!user?.locales || !locale.district) {
                handleError(
                    new Error(
                        "getRepresentatives: no user locales or no locale district",
                    ),
                    "Failed getting district.",
                );
                return;
            }

            if (!locale) {
                handleError(
                    new Error(`getRepresentatives: could not find user locale to get representatives.,
                ${JSON.stringify({ locale, locales: user.locales }, null, 4)}`),
                    "Failed getting locale.",
                );
                return;
            }

            const handleGetLegislators = (): Promise<
                sway.ILegislator[] | undefined | void
            > => {
                return new Promise((resolve) => {
                    setIsLoading(true);
                    resolve(true);
                })
                    .then(() => {
                        return swayFireClient(locale)
                            .legislators()
                            .representatives(
                                locale.district,
                                user.regionCode,
                                isActive,
                            );
                    })
                    .catch(handleError);
            };

            return makeCancellable(handleGetLegislators(), () => {
                logDev("Cancelled useHookedRepresentatives getRepresentatives");
            })
                .then((legislators) => {
                    if (!legislators) {
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
