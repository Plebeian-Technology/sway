import { useMemo } from "react";
import { Image } from "react-bootstrap";
import { sway } from "sway";
import { AWARDS, AWARD_ICONS } from "../../../utils";

interface IProps {
    userSway: sway.IUserSway;
}

const UserAwardsRow: React.FC<IProps> = ({ userSway }) => {
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

    const hasOneVote = userSway.countBillsVotedOn >= 1;
    const hasTenVotes = userSway.countBillsVotedOn >= 10;
    const hasHundredVotes = userSway.countBillsVotedOn >= 100;
    const sharedOneBill = userSway.countBillsShared >= 1;
    const sharedTenBill = userSway.countBillsShared >= 10;
    const sharedHundredBill = userSway.countBillsShared >= 100;
    const invitedOneBill = userSway.countInvitesSent >= 1;
    const invitedTenBill = userSway.countInvitesSent >= 10;
    const invitedHundredBill = userSway.countInvitesSent >= 100;

    const awards = useMemo(
        () => [
            hasOneVote,
            hasTenVotes,
            hasHundredVotes,
            sharedOneBill,
            sharedTenBill,
            sharedHundredBill,
            invitedOneBill,
            invitedTenBill,
            invitedHundredBill,
        ],
        [
            hasOneVote,
            hasTenVotes,
            hasHundredVotes,
            sharedOneBill,
            sharedTenBill,
            sharedHundredBill,
            invitedOneBill,
            invitedTenBill,
            invitedHundredBill,
        ],
    );

    const cells = useMemo(
        () =>
            awards.map(Boolean).map((_award: boolean, index: number) => {
                return (
                    <div key={AWARDS[index]} className="row align-items-center my-1">
                        <div className="col-2 col-sm-2 col-md-1 col-lg-1 col-xl-1 ps-0">
                            <Image
                                src={AWARD_ICONS[index]}
                                alt={"award"}
                                roundedCircle
                                thumbnail
                                className="p-0"
                            />
                        </div>
                        <div className="col-10 col-sm-10 col-md-11 col-lg-11 col-xl-11 px-0">
                            &nbsp;{AWARDS[index]}
                        </div>
                    </div>
                );
            }),
        [awards],
    );

    return <div className="row g-0">{cells}</div>;
};

export default UserAwardsRow;
