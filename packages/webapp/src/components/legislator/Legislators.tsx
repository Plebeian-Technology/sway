/** @format */

import {
    getUserLocales,
    isEmptyObject,
    isNotUsersLocale,
    toUserLocale,
} from "@sway/utils";
import { useEffect } from "react";
import { sway } from "sway";
import { useLocale } from "../../hooks";
import { useHookedRepresentatives } from "../../hooks/legislators";
import FullWindowLoading from "../dialogs/FullWindowLoading";
import SwayFab from "../fabs/SwayFab";
import LocaleSelector from "../user/LocaleSelector";
import { ILocaleUserProps } from "../user/UserRouter";
import LegislatorCard from "./LegislatorCard";

const Legislators: React.FC<ILocaleUserProps> = ({ user }) => {
    const [locale, setLocale] = useLocale(user);
    const [
        legislators,
        getRepresentatives,
        isLoadingLegislators,
    ] = useHookedRepresentatives();

    useEffect(() => {
        if (!locale) return;
        const _isActive = true;
        getRepresentatives(user, toUserLocale(locale), _isActive);
    }, [user]);

    if (isLoadingLegislators) {
        return <FullWindowLoading message={"Loading Legislators..."} />;
    }
    if (!legislators) {
        return <FullWindowLoading message={"Finding Legislators..."} />;
    }
    if (!legislators && !user?.locales) {
        return (
            <div className={"legislators-list"}>
                <p className="no-legislators-message">
                    No Legislators. Are you logged in?
                </p>
            </div>
        );
    }
    if (isNotUsersLocale(user, locale)) {
        return <FullWindowLoading message={"Updating Legislators..."} />;
    }

    const { representatives, isActive } = legislators;

    const sorted = [...representatives].sort((a, b) =>
        a.legislator.district > b.legislator.district ? -1 : 1,
    );

    const render = isEmptyObject(representatives) ? (
        <p className="no-legislators-message">No Legislators</p>
    ) : (
        sorted.map(
            (
                legislatorWithScore: sway.ILegislatorWithUserScore,
                index: number,
            ) => (
                <LegislatorCard
                    key={index}
                    locale={locale}
                    user={user}
                    legislatorWithScore={legislatorWithScore}
                />
            ),
        )
    );

    const handleSetLegislatorLocale = (
        newLocale: sway.IUserLocale | sway.ILocale,
    ) => {
        setLocale(newLocale);
        getRepresentatives(user, toUserLocale(newLocale), isActive);
    };

    return (
        <>
            <div className={"locale-selector-container"}>
                <LocaleSelector
                    locale={locale}
                    setLocale={handleSetLegislatorLocale}
                    locales={getUserLocales(user)}
                    containerStyle={{ width: "90%" }}
                />
            </div>
            <div className={"legislators-list"}>{render}</div>
            <SwayFab user={user} />
        </>
    );
};

export default Legislators;
