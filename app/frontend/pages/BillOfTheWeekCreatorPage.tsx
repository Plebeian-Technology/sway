/** @format */
import { sway } from "sway";

import { LocalizationProvider } from "@mui/x-date-pickers";
import { AdapterDateFns } from "@mui/x-date-pickers/AdapterDateFns";
import BillOfTheWeekCreator from "app/frontend/components/bill/creator/BillOfTheWeekCreator";
import { ETab } from "app/frontend/components/bill/creator/constants";
import LayoutWithPage from "app/frontend/components/layouts/Layout";

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

const BillOfTheWeekCreatorPage = (props: IProps) => {
    return (
        <LocalizationProvider dateAdapter={AdapterDateFns}>
            <BillOfTheWeekCreator {...props} />
        </LocalizationProvider>
    );
};

const PageLayout = (page: React.JSX.Element) =>
    LayoutWithPage({ ...page, props: { ...(page.props as IProps), withFade: false } });
BillOfTheWeekCreatorPage.layout = PageLayout;
export default BillOfTheWeekCreatorPage;
