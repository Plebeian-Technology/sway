import { useMemo } from "react";
import { sway } from "sway";
import Bill from "../bill/Bill";
import { TDataOrganizationPositions } from "./types";

interface IProps {
    billFirestoreId: string;
    organizations: TDataOrganizationPositions;
    swaySummary: string;
}

const BillOfTheWeekCreatorPreview: React.FC<IProps> = ({
    billFirestoreId,
    organizations,
    swaySummary,
}) => {
    const orgs = useMemo((): sway.IOrganization[] => {
        return organizations.map((o) => ({
            name: o.value,
            iconPath: o.iconPath,
            positions: {
                [billFirestoreId]: {
                    billFirestoreId: billFirestoreId,
                    support: o.support || false,
                    summary: o.position,
                },
            },
        }));
    }, [billFirestoreId, organizations]);

    return (
        <>
            <hr />
            <div className="bolder h2">Bill of the Week Preview</div>
            <Bill
                billFirestoreId={billFirestoreId}
                preview={{
                    organizations: orgs,
                    swaySummary: swaySummary,
                }}
            />
        </>
    );
};

export default BillOfTheWeekCreatorPreview;
