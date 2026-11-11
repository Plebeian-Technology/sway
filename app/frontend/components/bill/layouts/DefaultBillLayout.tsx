import BillContent from "app/frontend/components/bill/BillContent";
import BillHeader from "app/frontend/components/bill/BillHeader";
import VotePanel from "app/frontend/components/bill/VotePanel";

import type { BillLayoutProps } from "app/frontend/components/bill/layouts/types";

// @lat: [[system-shape#Why the shell keeps one reading measure]]
const DefaultBillLayout: React.FC<BillLayoutProps> = ({
    bill,
    sponsor,
    organizations,
    user_vote,
    bill_score,
    isAwaitingScoreUpdate,
}) => (
    <div className="grid gap-6">
        <BillHeader bill={bill} sponsor={sponsor}>
            <VotePanel bill={bill} user_vote={user_vote} />
        </BillHeader>
        <BillContent
            bill={bill}
            bill_score={bill_score}
            isAwaitingScoreUpdate={isAwaitingScoreUpdate}
            organizations={organizations}
            userVote={user_vote}
        />
    </div>
);

export default DefaultBillLayout;
