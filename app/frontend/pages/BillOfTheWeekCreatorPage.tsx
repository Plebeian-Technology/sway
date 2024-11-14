/** @format */
import { sway } from "sway";

import { LocalizationProvider } from "@mui/x-date-pickers";
import { AdapterDayjs } from "@mui/x-date-pickers/AdapterDayjs";

import BillOfTheWeekCreator from "app/frontend/components/bill/creator/BillOfTheWeekCreator";
import "react-datepicker/dist/react-datepicker.css";
import { useEffect } from "react";
import { notify } from "app/frontend/sway_utils";

interface IProps {
    flash?: {
        notice?: string;
        alert?: string;
    };
    bills: sway.IBill[];
    bill: sway.IBill;
    legislators: sway.ILegislator[];
    legislatorVotes: sway.ILegislatorVote[];
    locale: sway.ISwayLocale;
    positions: sway.IOrganizationPosition[];
    user: sway.IUser;
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
        <LocalizationProvider dateAdapter={AdapterDayjs}>
            <BillOfTheWeekCreator {...props} />
        </LocalizationProvider>
    );
};

const BillOfTheWeekCreatorPage = BillOfTheWeekCreatorPage_;
export default BillOfTheWeekCreatorPage;
