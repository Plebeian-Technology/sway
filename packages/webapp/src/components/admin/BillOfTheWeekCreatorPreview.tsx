import { useMemo } from "react";
import { sway } from "sway";
import Bill from "../bill/Bill";
import { TDataOrganizationPositions } from "./types";

interface IProps {
    user: sway.IUserWithSettingsAdmin;
    bill: sway.IBill;
    locale: sway.ILocale;
    organizations: TDataOrganizationPositions;
}

const BillOfTheWeekCreatorPreview: React.FC<IProps> = ({ user, bill, locale, organizations }) => {
    const orgs = useMemo((): sway.IOrganization[] => {
        return organizations.map((o) => ({
            name: o.value,
            iconPath: o.iconPath,
            positions: {
                [bill.firestoreId]: {
                    billFirestoreId: bill.firestoreId,
                    support: o.support || false,
                    summary: o.position,
                },
            },
        }));
    }, [organizations]);

    return (
        <>
            <hr />
            <div className="bolder h2">Bill of the Week Preview</div>
            <Bill user={user.user} bill={bill} locale={locale} organizations={orgs} isPreview />
        </>
    );
};

export default BillOfTheWeekCreatorPreview;
