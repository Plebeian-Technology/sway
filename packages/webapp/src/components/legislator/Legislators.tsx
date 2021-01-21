/** @format */

import { CONGRESS_LOCALE_NAME, LOCALES } from "@sway/constants";
import { useEffect, useState } from "react";
import { sway } from "sway";
import { useHookedRepresentatives } from "../../hooks/legislators";
import { isEmptyObject } from "../../utils";
import { isCongressLocale, isNotUsersLocale } from "../../utils/locales";
import FullWindowLoading from "../dialogs/FullWindowLoading";
import SwayFab from "../fabs/SwayFab";
import LocaleSelector from "../user/LocaleSelector";
import { ILocaleUserProps } from "../user/UserRouter";
import LegislatorCard from "./LegislatorCard";

const Legislators: React.FC<ILocaleUserProps> = ({ user, locale }) => {
    const [
        legislators,
        dispatchRepresentatives,
        isLoadingLegislators,
        isActive,
    ] = useHookedRepresentatives();

    const [legislatorLocale, setLegislatorLocale] = useState<sway.ILocale>(locale);

    useEffect(() => {
        if (!user?.locale) return;
        const _isCongress = false;
        const _isActive = true
        dispatchRepresentatives(user, _isCongress, _isActive);
    }, [user])

    if (isLoadingLegislators) {
        return <FullWindowLoading message={"Loading Legislators..."} />;
    }
    if (!legislators) {
        return <FullWindowLoading message={"Finding Legislators..."} />;
    }
    if (isNotUsersLocale(user, locale)) {
        return <FullWindowLoading message={"Updating Legislators..."} />;
    }

    const sorted = [...legislators].sort((a, b) =>
        a.legislator.district > b.legislator.district ? -1 : 1,
    );

    const render = isEmptyObject(legislators) ? (
        <p className="no-legislators-message">No Legislators</p>
    ) : (
        sorted.map(
            (
                legislatorWithScore: sway.ILegislatorWithUserScore,
                index: number,
            ) => (
                <LegislatorCard
                    key={index}
                    locale={{ name: user?.locale?.name } as sway.ILocale}
                    user={user}
                    legislatorWithScore={legislatorWithScore}
                />
            ),
        )
    );

    const getLocales = () => {
        if (!user || !user?.locale?.name) {
            return LOCALES;
        }
        return LOCALES.filter(
            (l) =>
                l.name === user?.locale?.name ||
                l.name === CONGRESS_LOCALE_NAME,
        );
    };

    const handleSetLegislatorLocale = (newLocale: sway.ILocale) => {
        setLegislatorLocale(newLocale);
        dispatchRepresentatives(user, isCongressLocale(newLocale), isActive)
    }

    return (
        <>
            <div className={"locale-selector-container"}>
                <LocaleSelector
                    locale={legislatorLocale}
                    setLocale={handleSetLegislatorLocale}
                    locales={getLocales()}
                    containerStyle={{ width: "90%" }}
                />
            </div>
            <div className={"legislators-list"}>{render}</div>
            <SwayFab user={user} />
        </>
    );
};

export default Legislators;
