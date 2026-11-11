import { ETab } from "app/frontend/components/bill/creator/constants";
import BillCreatorShell from "app/frontend/components/admin/creator/BillCreatorShell";
import { sway } from "sway";

interface IProps {
    flash?: { notice?: string; alert?: string };
    bills: sway.IBill[];
    bill: sway.IBill & { organizations: sway.IOrganization[] };
    legislators: sway.ILegislator[];
    legislator_votes: sway.ILegislatorVote[];
    organizations: sway.IOrganization[];
    user: sway.IUser;
    tab_key?: string;
}

const VALID_TABS = new Set<string>(Object.values(ETab));

// @lat: [[bill-creator-tab-url-routing#Why BillCreatorPage.tsx translates tab_key client-side]]
const normalizeTabKey = (raw?: string): ETab => {
    if (raw === "pipeline_llm") return ETab.PipelineLlm;
    if (raw && VALID_TABS.has(raw)) return raw as ETab;
    return ETab.Creator;
};

// @lat: [[bill-creator-tab-url-routing#Why BillCreatorPage.tsx translates tab_key client-side]]
const BillCreatorPage: React.FC<IProps> = ({ user, tab_key }) => {
    if (!user?.is_admin) {
        return null;
    }
    return <BillCreatorShell tabKey={normalizeTabKey(tab_key)} />;
};

export default BillCreatorPage;
