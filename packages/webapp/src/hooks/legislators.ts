/** @format */

import { createSelector } from "@reduxjs/toolkit";
import {
    CONGRESS_LOCALE_NAME
} from "@sway/constants";
import { removeTimestamps } from "@sway/utils";
import { useCallback, useState } from "react";
import { useDispatch, useSelector } from "react-redux";
import { sway } from "sway";
import { setRepresentatives } from "../redux/actions/legislatorActions";
import { handleError, legisFire } from "../utils";

interface ILegislatorState {
    legislators: sway.ILegislator[];
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
    sway.ILegislatorWithUserScore[],
    (
        user: sway.IUser | undefined,
        isCongress: boolean,
        active: boolean,
    ) => void,
    boolean,
    boolean,
] => {
    const dispatch = useDispatch();
    const reps = useSelector(representativesSelector);
    const [isLoading, setIsLoading] = useState<boolean>(false);

    const withoutTimestamps = (lwus: sway.ILegislatorWithUserScore) => {
        const { score, legislator } = lwus;
        return {
            score,
            legislator: removeTimestamps(legislator),
        };
    };

    const dispatchRepresentatives = useCallback(
        async (
            user: sway.IUser | undefined,
            isCongress: boolean,
            isActive: boolean,
        ) => {
            if (!user?.locales) return;

            const locale = user.locales.find((l) => {
                return isCongress
                    ? l.name === CONGRESS_LOCALE_NAME
                    : l.name !== CONGRESS_LOCALE_NAME;
            });
            if (!locale) {
                console.error(
                    "could not find user locale to get representatives.",
                    { locales: user.locales, isCongress },
                );
                return;
            }

            setIsLoading(true);
            const getter = legisFire(locale)
                .legislators()
                .representatives(
                    user.uid,
                    locale.district,
                    locale.regionCode,
                    isActive,
                );

            getter
                .then((legislators) => {
                    if (!legislators) {
                        return;
                    }

                    const filtered = legislators.filter(
                        Boolean,
                    ) as sway.ILegislatorWithUserScore[];

                    dispatch(
                        setRepresentatives({
                            representatives: filtered.map(withoutTimestamps),
                            isActive,
                        }),
                    );
                })
                .catch(handleError)
                .finally(() => setIsLoading(false));
        },
        [dispatch, setIsLoading],
    );

    return [reps, dispatchRepresentatives, isLoading, useIsActive()];
};
