/** @format */

import React from "react";
import { useParams } from "react-router-dom";
import { sway } from "sway";
import { swayFireClient } from "../../utils";
import SwayFab from "../fabs/SwayFab";
import LegislatorCard from "./LegislatorCard";
import { findLocale } from "@sway/utils";

const Legislator: React.FC<{ user: sway.IUser | undefined }> = ({ user }) => {
    const { localeName, externalLegislatorId } = useParams<sway.IPlainObject>();
    const [
        legislator,
        setLegislator,
    ] = React.useState<sway.ILegislator | void>();

    const locale = findLocale(localeName);
    if (!locale) {
        console.error(
            `Locale with name - ${localeName} - not in LOCALES. Skip getting Legislator with id - ${externalLegislatorId}.`,
        );
        return null;
    }

    React.useEffect(() => {
        if (!externalLegislatorId) return;

        const getLegislator = async () => {
            const _legislator: sway.ILegislator | void = await swayFireClient(locale)
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
