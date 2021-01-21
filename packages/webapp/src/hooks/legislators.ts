/** @format */

import { createSelector } from "@reduxjs/toolkit";
import { CONGRESS_LOCALE, STATE_CODES_NAMES } from "@sway/constants";
import { useCallback, useState } from "react";
import { useDispatch, useSelector } from "react-redux";
import { sway } from "sway";
import { setRepresentatives } from "../redux/actions/legislatorActions";
import { handleError, legisFire, removeTimestamps } from "../utils";

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
            if (!user?.locale) return;

            const {
                name,
                district,
                congressionalDistrict,
                _region,
            } = user.locale;
            const _district = isCongress ? congressionalDistrict : district;

            if (!_district) return;

            const _locale = isCongress ? CONGRESS_LOCALE : { name } as sway.ILocale;
            const _regionCode =
                _region.length === 2 ? _region : STATE_CODES_NAMES[_region];

            setIsLoading(true);
            const getter = legisFire(_locale)
                .legislators()
                .representatives(user.uid, _district, _regionCode, isActive);

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
