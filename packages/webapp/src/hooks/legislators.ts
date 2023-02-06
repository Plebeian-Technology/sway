/** @format */

import { isEmptyObject, logDev, toFormattedLocaleName } from "@sway/utils";
import { useCallback, useState } from "react";
import { sway } from "sway";
import { handleError, removeTimestamps } from "../utils";
import { useCancellable } from "./cancellable";
import { useLocaleName } from "./locales";
import { useUserLocaleDistrict, useUserLocaleRegionCode } from "./locales/useUserLocale";
import { useSwayFireClient } from "./useSwayFireClient";

const DEFAULT_LEGISLATORS = [] as sway.ILegislator[];

export const useRepresentatives = (): [sway.ILegislator[], (a: boolean) => void, boolean] => {
    const makeCancellable = useCancellable();
    const fire = useSwayFireClient();
    const localeName = useLocaleName();
    const userLocaleDistrict = useUserLocaleDistrict();
    const userLocaleRegionCode = useUserLocaleRegionCode();

    const [representatives, setRepresentatives] = useState<sway.ILegislator[]>(DEFAULT_LEGISLATORS);
    const [isLoading, setLoading] = useState<boolean>(false);

    const handleGetLegislators = useCallback(
        async (isActive: boolean): Promise<sway.ILegislator[]> => {
            logDev("userLocaleDistrict", {
                userLocaleDistrict,
                userLocaleRegionCode,
                locale: fire.locale?.name,
            });

            if (!userLocaleDistrict || !userLocaleRegionCode) {
                return [];
            }

            return fire
                .legislators()
                .representatives(
                    userLocaleDistrict.replace(userLocaleRegionCode, ""),
                    userLocaleRegionCode,
                    isActive,
                )
                .catch((e) => {
                    handleError(e);
                    return [];
                });
        },
        [fire, userLocaleDistrict, userLocaleRegionCode],
    );

    const getRepresentatives = useCallback(
        (isActive: boolean) => {
            setLoading(true);

            makeCancellable(handleGetLegislators(isActive))
                .then((legislators) => {
                    setLoading(false);
                    if (isEmptyObject(legislators)) {
                        console.error(
                            `No legislators found in ${toFormattedLocaleName(localeName)}`,
                        );
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
        [makeCancellable, handleGetLegislators, localeName],
    );

    return [representatives, getRepresentatives, isLoading];
};
