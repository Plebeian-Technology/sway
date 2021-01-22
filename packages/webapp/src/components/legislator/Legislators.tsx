/** @format */

import { getUserLocales, isCongressLocale, isEmptyObject, isNotUsersLocale } from "@sway/utils";
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
    const [
        legislators,
        dispatchRepresentatives,
        isLoadingLegislators,
        isActive,
    ] = useHookedRepresentatives();
    const [locale, setLocale] = useLocale(user);

    useEffect(() => {
        if (!locale) return;
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
                    locale={{ name: locale.name } as sway.ILocale}
                    user={user}
                    legislatorWithScore={legislatorWithScore}
                />
            ),
        )
    );

    const handleSetLegislatorLocale = (newLocale: sway.ILocale) => {
        setLocale(newLocale);
        dispatchRepresentatives(user, isCongressLocale(newLocale), isActive)
    }

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
