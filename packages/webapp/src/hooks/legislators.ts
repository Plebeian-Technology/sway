/** @format */

import { createSelector } from "@reduxjs/toolkit";
import { ESwayLevel } from "@sway/constants";
import { useCallback, useEffect, useState } from "react";
import { useDispatch, useSelector } from "react-redux";
import { sway } from "sway";
import { setRepresentatives } from "../redux/actions/legislatorActions";
import { handleError, legisFire, removeTimestamps } from "../utils";

interface ILegislatorState {
    legislators: sway.ILegislator[];
    representatives: sway.ILegislatorWithUserScore[];
    isActive: boolean;
    level: ESwayLevel;
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

const levelSelector = createSelector(
    [lState],
    (legislatorState: ILegislatorState) => legislatorState.level,
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

export const useLevel = () => {
    return useSelector(levelSelector) || ESwayLevel.Local;
};

export const useHookedRepresentatives = (
    user: sway.IUser | undefined,
): [
    sway.ILegislatorWithUserScore[],
    (
        _uid: string | undefined,
        _localeName: string | undefined,
        _district: number | null | undefined,
        active: boolean,
        level: ESwayLevel,
    ) => void,
    boolean,
    boolean,
    ESwayLevel,
] => {
    const dispatch = useDispatch();
    const reps = useSelector(representativesSelector);
    const [isLoading, setIsLoading] = useState<boolean>(false);

    const uid = user?.uid;
    const localeName = user?.locale?.name;
    const district = user?.locale?.district;

    const toLegislatorAndScore = (lwus: sway.ILegislatorWithUserScore) => {
        const { score, legislator } = lwus;
        return {
            score,
            legislator: removeTimestamps(legislator),
        };
    };

    const getRepresentatives = useCallback(
        async (
            _uid: string | undefined,
            _localeName: string | undefined,
            _district: number | null | undefined,
            active: boolean,
            level: ESwayLevel,
        ) => {
            if (!_uid || !_localeName || !_district) return;
            setIsLoading(true);

            const _locale = { name: _localeName } as sway.ILocale;

            const getter = legisFire(_locale)
                .legislators()
                .representatives(_uid, _district, active);

            getter
                .then((legislators) => {
                    if (!legislators) {
                        setIsLoading(false);
                        return;
                    }

                    const filtered = legislators.filter(
                        Boolean,
                    ) as sway.ILegislatorWithUserScore[];

                    dispatch(
                        setRepresentatives({
                            representatives: filtered.map(toLegislatorAndScore),
                            isActive: active,
                            level,
                        }),
                    );
                    setIsLoading(false);
                })
                .catch(handleError);
        },
        [dispatch, setIsLoading],
    );

    useEffect(() => {
        getRepresentatives(
            uid,
            localeName,
            district,
            true,
            ESwayLevel.Local,
        ).catch(console.error);
    }, [uid, localeName, district, getRepresentatives]);

    return [reps, getRepresentatives, isLoading, useIsActive(), useLevel()];
};
