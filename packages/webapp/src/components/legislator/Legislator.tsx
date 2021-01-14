/** @format */

import React from "react";
import { useParams } from "react-router-dom";
import { sway } from "sway";
import { legisFire } from "../../utils";
import SwayFab from "../fabs/SwayFab";
import { ILocaleUserProps } from "../user/UserRouter";
import LegislatorCard from "./LegislatorCard";

const Legislator: React.FC<ILocaleUserProps> = ({ locale, user, }) => {
    const { externalLegislatorId } = useParams<sway.IPlainObject>();
    const [
        legislator,
        setLegislator,
    ] = React.useState<sway.ILegislator | void>();

    React.useEffect(() => {
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
    }, [locale, externalLegislatorId, setLegislator]);

    if (!locale || !externalLegislatorId || !legislator) return null;

    return (
        <div className={"legislators-list"}>
            <LegislatorCard
                locale={locale}
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
