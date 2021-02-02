import {
    Avatar,
    Tooltip,
    createStyles,
    makeStyles,
    withStyles,
    Theme,
    Grid,
} from "@material-ui/core";
import React from "react";
import { sway } from "sway";

const AWARDS = [
    "Voted on a Bill of the Week",
    "Voted on 10 Bills of the Week",
    "Voted on 100 Bills of the Week",
    "Shared a Bill of the Week",
    "Shared 10 Bills of the Week",
    "Shared 100 Bills of the Week",
    "Invited 1 Friend",
    "Invited 10 Friends",
    "Invited 100 Friends",
    "Sway Rank 1",
    "Sway Rank 2",
    "Sway Rank 3",
];

const AWARD_ICONS = [
    "/avatars/awards/ballotbox.png",
    "/avatars/awards/ballotbox.png",
    "/avatars/awards/ballotbox.png",
    "/avatars/awards/thepeople.png",
    "/avatars/awards/thepeople.png",
    "/avatars/awards/thepeople.png",
    "/avatars/awards/torch-blue.png",
    "/avatars/awards/torch-red.png",
    "/avatars/awards/torch-black.png",
    "/avatars/awards/crown-blue.png",
    "/avatars/awards/crown-red.png",
    "/avatars/awards/crown-red.png",
];

const AwardTooltip = withStyles((theme: Theme) => ({
    tooltip: {
        fontSize: theme.spacing(2),
    },
}))(Tooltip);

interface IProps {
    user: sway.IUser;
    userSway: sway.IUserSway;
    localeSway: sway.IUserSway;
}

const useStyles = makeStyles((theme: Theme) => {
    return createStyles({
        cell: {
            padding: theme.spacing(1),
        },
    });
});

const UserAwardsRow: React.FC<IProps> = ({ user, userSway, localeSway }) => {
    const classes = useStyles();

    const uids = localeSway.uids; // can contain duplicates, 1 uid per bill shared
    const userUidsInLocale = uids.filter((u) => u === user.uid);
    console.log("(dev) Count of user uids =", userUidsInLocale.length);

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
    const invitedOneBill = userSway.countInvitesUsed >= 1;
    const invitedTenBill = userSway.countInvitesUsed >= 10;
    const invitedHundredBill = userSway.countInvitesUsed >= 100;

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

            const style = index === 0 ? {paddingLeft: 15} : {}
            return (
                <AwardTooltip
                    key={AWARDS[index]}
                    title={AWARDS[index]}
                    placement="bottom"
                >
                    <div className={classes.cell} style={style}>
                        <Grid item xs>
                            <Avatar src={AWARD_ICONS[index]} alt={"award"} />
                        </Grid>
                    </div>
                </AwardTooltip>
            );
        })
        .filter(Boolean);

    return (
        <Grid
            container
            direction="row"
            spacing={1}
            justify="flex-start"
            alignItems="center"
        >
            {cells}
        </Grid>
    );
};

export default UserAwardsRow;
