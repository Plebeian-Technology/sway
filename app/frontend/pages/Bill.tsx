import { router, usePage, usePoll } from "@inertiajs/react";
import { createElement, Suspense } from "react";

import { useActionCableReconnect } from "app/frontend/hooks/useActionCableReconnect";
import { useActiveThemeId } from "app/frontend/hooks/useActiveThemeId";
import { usePullToRefresh } from "app/frontend/hooks/usePullToRefresh";
import { useScoreSubscription } from "app/frontend/hooks/useScoreSubscription";
import BillEditLink from "app/frontend/components/bill/BillEditLink";
import { billLayoutFor } from "app/frontend/components/bill/layouts";
import { isArchivedHistoricalBill } from "app/frontend/components/bill/sway_utils/billArchiving";
import ThemeLayoutPlaceholder from "app/frontend/components/bill/ThemeLayoutPlaceholder";
import { sway } from "sway";

interface IProps {
    bill: sway.IBill;
    sponsor: sway.ILegislator;
    legislators?: sway.ILegislator[];
    organizations: sway.IBillOrganizationPosition[];
    legislator_votes: sway.ILegislatorVote[];
    user_vote?: sway.IUserVote;
    bill_score?: sway.IBillScore;
    districts?: sway.IDistrict[];
}

// @lat: [[client-caches-and-identity#Bill refresh feedback]]
const POLLING_PROPS = ["bill_score", "organizations", "user_legislator_emails"];

const Bill: React.FC<IProps> = ({ bill, sponsor, organizations, user_vote, bill_score }) => {
    const user = usePage<sway.IPageProps>().props?.user;
    usePoll(15000, { only: POLLING_PROPS }, { background: "pause" });
    const isAwaitingScoreUpdate = useScoreSubscription(POLLING_PROPS, Boolean(user));
    useActionCableReconnect(POLLING_PROPS);
    usePullToRefresh({ onRefresh: () => router.reload() });

    // @lat: [[client-caches-and-identity#Bill refresh feedback]]
    const layout = billLayoutFor(useActiveThemeId());

    return (
        <>
            {/* @lat: [[identity-and-access#Identity and access#The admin gate is a lint rule#An admin affordance in the reader's page is a convenience, not a gate]] */}
            <BillEditLink
                billId={bill.id}
                billIdentifier={bill.external_id}
                isArchived={isArchivedHistoricalBill(bill)}
                variant="detail"
            />
            <Suspense fallback={<ThemeLayoutPlaceholder shape="detail" />}>
                {createElement(layout, {
                    bill,
                    sponsor,
                    organizations,
                    user_vote,
                    bill_score,
                    isAwaitingScoreUpdate,
                })}
            </Suspense>
        </>
    );
};

export default Bill;
