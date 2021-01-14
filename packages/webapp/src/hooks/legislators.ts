/** @format */

import { createSelector } from "@reduxjs/toolkit";
import { useCallback, useEffect, useState } from "react";
import { useDispatch, useSelector } from "react-redux";
import { sway } from "sway";
import { setRepresentatives } from "../redux/actions/legislatorActions";
import { legisFire, removeTimestamps } from "../utils";

interface ILegislatorState {
    legislators: sway.ILegislator[];
    representatives: sway.ILegislatorWithUserScore[];
}

const state = (_state: sway.IAppState) => _state.legislators;

const representativesSelector = createSelector(
    [state],
    (legislatorState: ILegislatorState) => legislatorState.representatives,
);

export const useLegislators = () => {
    return useSelector(state);
};

export const useRepresentatives = () => {
    return useSelector(representativesSelector);
};

export const useHookedRepresentatives = (
    user: sway.IUser | undefined,
): [
    sway.ILegislatorWithUserScore[],
    (
        _uid: string | undefined,
        _localeName: string | undefined,
        _district: number | undefined,
        _active: boolean,
    ) => void,
    boolean,
] => {
    const dispatch = useDispatch();
    const reps = useSelector(representativesSelector);
    const [isLoading, setIsLoading] = useState<boolean>(false);
    const uid = user?.uid;
    const localeName = user?.locale?.name;
    const district = user?.locale?.district;

    const getRepresentatives = useCallback(
        async (
            _uid: string | undefined,
            _localeName: string | undefined,
            _district: number | undefined,
            active: boolean,
        ) => {
            if (!_uid || !_localeName || !_district) return;
            setIsLoading(true);

            const legislators: (
                | sway.ILegislatorWithUserScore
                | undefined
            )[] = await legisFire({ name: _localeName } as sway.ILocale)
                .legislators()
                .representatives(_uid, _district, active);

            if (!legislators) {
                setIsLoading(false);
            }

            const filtered = legislators.filter(
                Boolean,
            ) as sway.ILegislatorWithUserScore[];

            dispatch(
                setRepresentatives(
                    filtered.map((lwus: sway.ILegislatorWithUserScore) => {
                        const { score, legislator } = lwus;
                        return {
                            score,
                            legislator: removeTimestamps(legislator),
                        };
                    }) as sway.ILegislatorWithUserScore[],
                ),
            );
            setIsLoading(false);
        },
        [dispatch, setIsLoading],
    );

    useEffect(() => {
        if (!uid || !localeName || !district) return;

        getRepresentatives(uid, localeName, district, true).catch(
            console.error,
        );
    }, [uid, localeName, district, getRepresentatives]);

    return [reps, getRepresentatives, isLoading];
};
