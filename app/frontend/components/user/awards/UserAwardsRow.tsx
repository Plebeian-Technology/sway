import UserAward from "app/frontend/components/user/awards/UserAward";
import { AWARDS } from "app/frontend/sway_constants";
import { useMemo } from "react";
import { sway } from "sway";

interface IProps {
    influence: sway.IInfluence;
}

const UserAwardsRow: React.FC<IProps> = ({ influence }) => {
    // awards
    // * voted on a bill - blue ballot box
    // * voted on 10 active bills - red ballot box
    // * voted on 100 active bills - black ballot box
    // * shared a bill - blue thepeople
    // * shared 10 active bills - red thepeople
    // * shared 100 active bills - black thepeople
    // * invited a user - blue torch
    // * invited 10 users - red torch
    // * invited 100 users - black torch
    // * Level of Sway
    // ** #1 - blue crown
    // ** #2 - red crown
    // ** #3 - black crown

    const hasOneVote = (influence.countBillsVotedOn ?? 0) >= 1;
    const hasTenVotes = (influence.countBillsVotedOn ?? 0) >= 10;
    const hasHundredVotes = (influence.countBillsVotedOn ?? 0) >= 100;
    const sharedOneBill = (influence.countBillsShared ?? 0) >= 1;
    const sharedTenBill = (influence.countBillsShared ?? 0) >= 10;
    const sharedHundredBill = (influence.countBillsShared ?? 0) >= 100;

    const awards = useMemo(
        () => [hasOneVote, hasTenVotes, hasHundredVotes, sharedOneBill, sharedTenBill, sharedHundredBill],
        [hasOneVote, hasTenVotes, hasHundredVotes, sharedOneBill, sharedTenBill, sharedHundredBill],
    );

    const cells = useMemo(
        () =>
            awards
                .filter(Boolean)
                .map((_award: boolean, index: number) => <UserAward key={AWARDS[index]} index={index} />),
        [awards],
    );

    return <div className="row g-0">{cells}</div>;
};

export default UserAwardsRow;
