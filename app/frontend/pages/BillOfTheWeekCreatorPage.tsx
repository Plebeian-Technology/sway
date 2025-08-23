/** @format */
import { sway } from "sway";

import { LocalizationProvider } from "@mui/x-date-pickers";
import { AdapterDateFns } from "@mui/x-date-pickers/AdapterDateFns";

import BillOfTheWeekCreator from "app/frontend/components/bill/creator/BillOfTheWeekCreator";
import { useEffect } from "react";
import { notify } from "app/frontend/sway_utils";
import { ETab } from "app/frontend/components/bill/creator/constants";

interface IProps {
    flash?: {
        notice?: string;
        alert?: string;
    };
    bills: sway.IBill[];
    bill: sway.IBill & { organizations: sway.IOrganization[] };
    legislators: sway.ILegislator[];
    legislator_votes: sway.ILegislatorVote[];
    locale: sway.ISwayLocale;
    organizations: sway.IOrganization[];
    user: sway.IUser;
    tab_key: ETab;
}

const BillOfTheWeekCreatorPage_: React.FC<IProps> = ({ flash, ...props }) => {
    useEffect(() => {
        if (flash?.notice) {
            notify({
                level: "success",
                title: flash.notice,
            });
        }
        if (flash?.alert) {
            notify({
                level: "error",
                title: flash.alert,
            });
        }
    }, [flash]);

    return (
        <LocalizationProvider dateAdapter={AdapterDateFns}>
            <BillOfTheWeekCreator {...props} />
        </LocalizationProvider>
    );
};

const BillOfTheWeekCreatorPage = BillOfTheWeekCreatorPage_;
export default BillOfTheWeekCreatorPage;
