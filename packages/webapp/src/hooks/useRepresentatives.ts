/** @format */

import { isEmptyObject, logDev, toFormattedLocaleName } from "@sway/utils";
import { useCallback, useState } from "react";
import { sway } from "sway";
import { handleError, removeTimestamps } from "../utils";
import { useCancellable } from "./useCancellable";
import { useLocaleName } from "./useLocales";
import { useUserLocaleDistrict, useUserLocaleRegionCode } from "./locales/useUserLocale";
import { useSwayFireClient } from "./useSwayFireClient";

const DEFAULT_LEGISLATORS = [] as sway.ILegislator[];

export const useRepresentatives = () => {
    const makeCancellable = useCancellable();
    const fire = useSwayFireClient();
    const localeName = useLocaleName();
    const userLocaleDistrict = useUserLocaleDistrict();
    const userLocaleRegionCode = useUserLocaleRegionCode();

    const [representatives, setRepresentatives] = useState<sway.ILegislator[]>(DEFAULT_LEGISLATORS);
    const [isLoading, setLoading] = useState<boolean>(false);
    const [isLoaded, setLoaded] = useState<boolean>(false);

    const handleGetLegislators = useCallback(
        async (isActive: boolean): Promise<sway.ILegislator[]> => {
            logDev("useRepresentatives.handleGetLegislators", {
                userLocaleDistrict,
                userLocaleRegionCode,
                isActive,
                district: userLocaleDistrict.replace(userLocaleRegionCode, ""),
                locale: localeName,
            });

            if (!userLocaleDistrict || !userLocaleRegionCode) {
                logDev(
                    "useRepresentatives.handleGetLegislators - NO userLocaleDistrict OR NO userLocaleRegionCode. Skip getting legislators.",
                );
                return [];
            }

            return fire
                .legislators()
                .representatives(
                    userLocaleDistrict.replace(userLocaleRegionCode, ""),
                    userLocaleRegionCode,
                    isActive,
                )
                .then((newRepresentatives) => {
                    setLoaded(true);
                    return newRepresentatives;
                })
                .catch((e) => {
                    handleError(e);
                    setLoaded(true);
                    return [];
                });
        },
        [fire, localeName, userLocaleDistrict, userLocaleRegionCode],
    );

    const getRepresentatives = useCallback(
        (isActive: boolean) => {
            setLoading(true);

            makeCancellable(handleGetLegislators(isActive))
                .then((legislators) => {
                    logDev("useRepresentatives.getRepresentatives.legislators", legislators);
                    setLoading(false);
                    if (isEmptyObject(legislators)) {
                        if (isLoaded) {
                            console.error(
                                `No legislators found in ${toFormattedLocaleName(localeName)}`,
                            );
                        } else {
                            // no-op
                        }
                    } else {
                        setRepresentatives(
                            legislators
                                .map(removeTimestamps)
                                .sort((a, b) => (a.district > b.district ? -1 : 1)),
                        );
                    }
                })
                .catch((error) => {
                    setLoading(false);
                    handleError(error);
                });
        },
        [makeCancellable, handleGetLegislators, localeName, isLoaded],
    );

    return { representatives, getRepresentatives, isLoading, isLoaded };
};
