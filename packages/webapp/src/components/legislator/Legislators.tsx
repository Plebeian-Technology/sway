/** @format */

import { sway } from "sway";
import { useHookedRepresentatives } from "../../hooks/legislators";
import { isEmptyObject } from "../../utils";
import FullWindowLoading from "../dialogs/FullWindowLoading";
import SwayFab from "../fabs/SwayFab";
import { ILocaleUserProps } from "../user/UserRouter";
import LegislatorCard from "./LegislatorCard";
import LegislatorsHeader from "./LegislatorsHeader";

const Legislators: React.FC<ILocaleUserProps> = ({ user, locale }) => {
    const [legislators, setLegislators, isLoadingLegislators] = useHookedRepresentatives(user);

    const isLoading =
        !locale.name ||
        isLoadingLegislators ||
        (user?.locale?.name && user.locale.name !== locale.name) ||
        isEmptyObject(legislators);

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

    return (
        <>
            <LegislatorsHeader
                user={user}
                setLegislators={setLegislators}
                isActive={
                    legislators[0] ? legislators[0]?.legislator?.active : true
                }
            />
            <div className={"legislators-list"}>{render}</div>
            <SwayFab user={user} />
        </>
    );
};

export default Legislators;
