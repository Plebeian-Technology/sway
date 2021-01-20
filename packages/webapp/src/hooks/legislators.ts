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
        _regionCode: string | undefined,
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
    const regionCode = user?.locale?.region;

    const withoutTimestamps = (lwus: sway.ILegislatorWithUserScore) => {
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
            _regionCode: string | undefined,
            active: boolean,
            level: ESwayLevel,
        ) => {
            if (!_uid || !_localeName || !_district || !_regionCode) return;
            setIsLoading(true);

            const _locale = { name: _localeName } as sway.ILocale;

            console.log("_uid", _uid);
            console.log("_district", _district);
            console.log("_regionCode", _regionCode);

            const getter = legisFire(_locale)
                .legislators()
                .representatives(_uid, _district, _regionCode, active);

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
                            representatives: filtered.map(withoutTimestamps),
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
            regionCode,
            true,
            ESwayLevel.Local,
        ).catch(console.error);
    }, [uid, localeName, district, regionCode, getRepresentatives]);

    return [reps, getRepresentatives, isLoading, useIsActive(), useLevel()];
};
