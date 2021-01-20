/** @format */

import { CONGRESS_LOCALE_NAME, LOCALES } from "@sway/constants";
import { sway } from "sway";
import { useHookedRepresentatives } from "../../hooks/legislators";
import { isEmptyObject } from "../../utils";
import FullWindowLoading from "../dialogs/FullWindowLoading";
import SwayFab from "../fabs/SwayFab";
import LocaleSelector from "../user/LocaleSelector";
import { ILocaleUserProps } from "../user/UserRouter";
import LegislatorCard from "./LegislatorCard";

const Legislators: React.FC<ILocaleUserProps> = ({ user, locale }) => {
    const [
        legislators,
        setLegislators,
        isLoadingLegislators,
        isActive,
    ] = useHookedRepresentatives(user);

    const isLoading =
        !locale.name ||
        isLoadingLegislators ||
        !legislators ||
        (user?.locale?.name && user.locale.name !== locale.name);

    if (isLoading) {
        return <FullWindowLoading message={"Loading Legislators..."} />;
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

    return (
        <>
            <div className={"locale-selector-container"}>
                <LocaleSelector
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
