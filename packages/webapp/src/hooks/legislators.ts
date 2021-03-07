/** @format */

import { removeTimestamps } from "@sway/utils";
import { useCallback, useState } from "react";
import { sway } from "sway";
import { handleError, swayFireClient } from "../utils";

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
    ) => void,
    boolean,
] => {
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
            if (!user?.locales || !locale.district) return;

            if (!locale) {
                console.error(
                    "could not find user locale to get representatives.",
                    { locale, locales: user.locales },
                );
                return;
            }

            setIsLoading(true);
            const getter = swayFireClient(locale)
                .legislators()
                .representatives(locale.district, user.regionCode, isActive);

            getter
                .then((legislators) => {
                    if (!legislators) return;

                    setReps({
                        representatives: legislators.map(withoutTimestamps),
                        isActive,
                    });
                })
                .catch(handleError)
                .finally(() => setIsLoading(false));
        },
        [setReps, setIsLoading],
    );

    return [reps, getRepresentatives, isLoading];
};
