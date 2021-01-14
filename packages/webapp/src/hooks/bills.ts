import { useEffect, useState } from "react";
import { sway } from "sway";
import { legisFire } from "../utils";

export const useBillOfTheWeek = (locale: sway.ILocale | sway.IUserLocale | null | undefined) => {
    const [botw, setBotw] = useState<
        sway.IBillWithOrgs | undefined
    >();

    const localeName = locale?.name;

    useEffect(() => {
        const load = async () => {
            if (!localeName) return;
            const _locale = { name: localeName } as sway.ILocale;
            const bill: sway.IBill | void = await legisFire(_locale)
                .bills()
                .latest();

            if (!bill) return;

            const organizations = await legisFire(_locale)
                .organizations()
                .listPositions(bill.firestoreId);

            setBotw({ bill, organizations });
        };
        localeName && load();
    }, [localeName]);

    return botw;
};
