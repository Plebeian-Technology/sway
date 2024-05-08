import { useMemo } from "react";
import { sway } from "sway";
import Bill from "../../pages/Bill";
import { TDataOrganizationPositions } from "./types";
import BillComponent from "app/frontend/components/bill/BillComponent";

interface IProps {
    bill: sway.IBill;
    organizations: TDataOrganizationPositions;
    summary: string;
}

const BillOfTheWeekCreatorPreview: React.FC<IProps> = ({
    bill,
    organizations,
    summary,
}) => {
    const orgs = useMemo((): sway.IOrganization[] => {
        return organizations.map((o) => ({
            name: o.value,
            iconPath: o.iconPath,
            positions: {
                [bill.externalId]: {
                    billExternalId: bill.externalId,
                    support: o.support || false,
                    summary: o.position,
                },
            },
        }));
    }, [bill.externalId, organizations]);

    return (
        <>
            <hr />
            <div className="bolder h2">Bill of the Week Preview</div>
            <BillComponent
                bill={bill}
                // preview={{
                //     organizations: orgs,
                //     summary: summary,
                // }}
            />
        </>
    );
};

export default BillOfTheWeekCreatorPreview;
