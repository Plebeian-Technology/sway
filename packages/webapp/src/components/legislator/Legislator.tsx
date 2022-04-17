/** @format */

import { findLocale } from "@sway/utils";
import { useEffect, useState } from "react";
import { useParams } from "react-router-dom";
import { sway } from "sway";
import { swayFireClient } from "../../utils";
import SwayFab from "../fabs/SwayFab";
import LegislatorCard from "./LegislatorCard";

const Legislator: React.FC<{ user: sway.IUser | undefined }> = ({ user }) => {
    const { localeName, externalLegislatorId } = useParams<sway.IPlainObject>();
    const [legislator, setLegislator] = useState<sway.ILegislator | void>();

    const locale = findLocale(localeName);
    if (!locale) {
        console.error(
            `Locale with name - ${localeName} - not in LOCALES. Skip getting Legislator with id - ${externalLegislatorId}.`,
        );
        return null;
    }

    useEffect(() => {
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
        <>
            <LegislatorCard locale={locale} user={user} legislator={legislator} />
            <SwayFab user={user} />
        </>
    );
};

export default Legislator;
