/** @format */

import React from "react";
import { useParams } from "react-router-dom";
import { sway } from "sway";
import { legisFire } from "../../utils";
import SwayFab from "../fabs/SwayFab";
import LegislatorCard from "./LegislatorCard";

const Legislator: React.FC<{user: sway.IUser | undefined}> = ({ user, }) => {
    console.log("LEGISLATOR");

    const { localeName, externalLegislatorId } = useParams<sway.IPlainObject>();
    const [
        legislator,
        setLegislator,
    ] = React.useState<sway.ILegislator | void>();

    React.useEffect(() => {
        const locale = { name: localeName } as sway.ILocale;
        if (!locale || !externalLegislatorId) return;

        const getLegislator = async () => {
            const _legislator: sway.ILegislator | void = await legisFire(
                locale
            )
                .legislators()
                .get(externalLegislatorId);

            if (_legislator) setLegislator(_legislator);
        };
        getLegislator().catch(console.error);
    }, [localeName, externalLegislatorId, setLegislator]);

    if (!localeName || !externalLegislatorId || !legislator) return null;

    return (
        <div className={"legislators-list"}>
            <LegislatorCard
                locale={{ name: localeName } as sway.ILocale}
                user={user}
                legislatorWithScore={{
                    legislator,
                    score: undefined,
                }}
            />
            <SwayFab user={user} />
        </div>
    );
};

export default Legislator;
