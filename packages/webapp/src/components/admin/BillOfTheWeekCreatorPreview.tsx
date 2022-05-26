import { useMemo } from "react";
import { sway } from "sway";
import Bill from "../bill/Bill";
import { IDataOrganizationPositions } from "./types";

interface IProps {
    user: sway.IUserWithSettingsAdmin;
    bill: sway.IBill;
    locale: sway.ILocale;
    // organizations: sway.IOrganization[];
    organizations: IDataOrganizationPositions;
}

const BillOfTheWeekCreatorPreview: React.FC<IProps> = ({ user, bill, locale, organizations }) => {
    const orgs = useMemo((): sway.IOrganization[] => {
        return Object.keys(organizations).map((key) => ({
            name: organizations[key].label,
            iconPath: "",
            positions: {
                [bill.firestoreId]: {
                    billFirestoreId: bill.firestoreId,
                    support: organizations[key].support || false,
                    summary: organizations[key].position,
                },
            },
        }));
    }, [organizations]);

    return (
        <>
            <hr />
            <div className="bolder h2">Bill of the Week Preview</div>
            <Bill user={user.user} bill={bill} locale={locale} organizations={orgs} />
        </>
    );
};

export default BillOfTheWeekCreatorPreview;
