import { makeStyles, withStyles } from "@mui/styles";
import { Avatar, Theme, Tooltip } from "@mui/material";
import { logDev } from "src/utils";
import { sway } from "sway";
import { AWARDS, AWARD_ICONS, IS_MOBILE_PHONE } from "../../../utils";

export const AwardTooltip = withStyles((theme: Theme) => ({
    tooltip: {
        fontSize: theme.spacing(2),
    },
}))(Tooltip);

interface IProps {
    user: sway.IUser;
    userSway: sway.IUserSway;
    localeSway: sway.IUserSway;
}

const opposite = IS_MOBILE_PHONE ? "column" : "row";

const useStyles = makeStyles((theme: Theme) => {
    return {
        cell: {
            padding: theme.spacing(1),
        },
        subcontainer: {
            display: "flex",
            flexDirection: opposite,
            alignItems: "center",
        },
    };
});

const UserAwardsRow: React.FC<IProps> = ({ user, userSway, localeSway }) => {
    const classes = useStyles();

    const uids = localeSway.uids; // can contain duplicates, 1 uid per bill shared
    const userUidsInLocale = uids.filter((u) => u === user.uid);
    logDev("Count of user uids in locale =", userUidsInLocale.length);

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

    const hasAwards = [
        hasOneVote,
        hasTenVotes,
        hasHundredVotes,
        sharedOneBill,
        sharedTenBill,
        sharedHundredBill,
        invitedOneBill,
        invitedTenBill,
        invitedHundredBill,
    ];

    const cells = hasAwards
        .map((award: boolean, index: number) => {
            if (!award) return;

            return (
                <AwardTooltip
                    key={AWARDS[index]}
                    title={AWARDS[index]}
                    placement="bottom"
                >
                    <div className={classes.cell}>
                        <Avatar src={AWARD_ICONS[index]} alt={"award"} />
                    </div>
                </AwardTooltip>
            );
        })
        .filter(Boolean);

    return <div className={classes.subcontainer}>{cells}</div>;
};

export default UserAwardsRow;
