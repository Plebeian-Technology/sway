import { useMemo } from "react";
import { sway } from "sway";
import Bill from "../../pages/Bill";
import { TDataOrganizationPositions } from "./types";

interface IProps {
    billExternalId: string;
    organizations: TDataOrganizationPositions;
    swaySummary: string;
}

const BillOfTheWeekCreatorPreview: React.FC<IProps> = ({
    billExternalId,
    organizations,
    swaySummary,
}) => {
    const orgs = useMemo((): sway.IOrganization[] => {
        return organizations.map((o) => ({
            name: o.value,
            iconPath: o.iconPath,
            positions: {
                [billExternalId]: {
                    billExternalId: billExternalId,
                    support: o.support || false,
                    summary: o.position,
                },
            },
        }));
    }, [billExternalId, organizations]);

    return (
        <>
            <hr />
            <div className="bolder h2">Bill of the Week Preview</div>
            <Bill
                billExternalId={billExternalId}
                preview={{
                    organizations: orgs,
                    swaySummary: swaySummary,
                }}
            />
        </>
    );
};

export default BillOfTheWeekCreatorPreview;
