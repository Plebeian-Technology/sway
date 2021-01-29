/** @format */

import { createSelector } from "@reduxjs/toolkit";
import { removeTimestamps } from "@sway/utils";
import { useCallback, useState } from "react";
import { useSelector } from "react-redux";
import { sway } from "sway";
import { handleError, swayFireClient } from "../utils";

interface ILegislatorState {
    legislators: sway.ILegislator[];
    representatives: sway.ILegislatorWithUserScore[];
    isActive: boolean;
}

interface IActiveRepresentatives {
    representatives: sway.ILegislatorWithUserScore[];
    isActive: boolean;
}

const lState = (_state: sway.IAppState) => _state.legislators;

const representativesSelector = createSelector(
    [lState],
    (legislatorState: ILegislatorState) => legislatorState.representatives,
);

const isActiveSelector = createSelector(
    [lState],
    (legislatorState: ILegislatorState) => legislatorState.isActive,
);

export const useLegislators = () => {
    return useSelector(lState);
};

export const useRepresentatives = () => {
    return useSelector(representativesSelector);
};

export const useIsActive = () => {
    return useSelector(isActiveSelector);
};

// TODO: Make user.locale user.locales
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

    const withoutTimestamps = (lwus: sway.ILegislatorWithUserScore) => {
        const { score, legislator } = lwus;
        return {
            score,
            legislator: removeTimestamps(legislator),
        };
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
                .representatives(
                    user.uid,
                    locale.district,
                    user.regionCode,
                    isActive,
                );

            getter
                .then((legislators) => {
                    if (!legislators) return;

                    const filtered = legislators.filter(
                        Boolean,
                    ) as sway.ILegislatorWithUserScore[];

                    setReps({
                        representatives: filtered.map(withoutTimestamps),
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
