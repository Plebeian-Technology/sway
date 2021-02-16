import {
    Avatar,
    createStyles,
    makeStyles,
    Theme,
    Typography
} from "@material-ui/core";
import Paper from "@material-ui/core/Paper";
import { Facebook, Telegram, Twitter, WhatsApp } from "@material-ui/icons";
import { CLOUD_FUNCTIONS } from "@sway/constants";
import { isEmptyObject, toFormattedLocaleName } from "@sway/utils";
import React, { useEffect, useState } from "react";
import { sway } from "sway";
import { functions } from "../../firebase";
import { handleError, IS_MOBILE_PHONE } from "../../utils";
import FullWindowLoading from "../dialogs/FullWindowLoading";
import { TSwaySvg } from "../SwaySvg";
import UserAwardsRow from "./awards/UserAwardsRow";

interface IProps {
    user: sway.IUser | undefined;
}

interface IResponseData {
    locale: sway.IUserLocale;
    userSway: sway.IUserSway;
    localeSway: sway.IUserSway;
}

const direction = IS_MOBILE_PHONE ? "row" : "column";
const opposite = IS_MOBILE_PHONE ? "column" : "row";
const dimension = IS_MOBILE_PHONE ? "height" : "width";

const useStyles = makeStyles((theme: Theme) => {
    return createStyles({
        container: {
            display: "flex",
            flexDirection: direction,
            justifyContent: "space-around",
            padding: theme.spacing(2),
        },
        subcontainer: {
            display: "flex",
            flexDirection: opposite,
            alignItems: "flex-end",
        },
        cell: {
            [dimension]: "10%",
            padding: theme.spacing(1),
        },
    });
});

const GridItem = ({
    text,
    Icon,
}: {
    text?: string | number;
    Icon?: TSwaySvg;
}) => {
    const classes = useStyles();

    if (text !== undefined) {
        return (
            <div className={classes.cell}>
                <Typography>{text}</Typography>
            </div>
        );
    }
    if (Icon) {
        return (
            <div className={classes.cell}>
                <Icon />
            </div>
        );
    }
    return null;
};

const UserInfluence: React.FC<IProps> = ({ user }) => {
    const classes = useStyles();
    const [sways, setSway] = useState<IResponseData[]>([]);

    useEffect(() => {
        user &&
            user.locales &&
            Promise.all(
                user.locales.map((userLocale: sway.IUserLocale) => {
                    const getter = functions.httpsCallable(
                        CLOUD_FUNCTIONS.getUserSway,
                    );
                    return getter({
                        uid: user.uid,
                        locale: userLocale,
                    });
                }),
            )
                .then(
                    (
                        responses: firebase.default.functions.HttpsCallableResult[],
                    ) => {
                        setSway(responses.map((r) => r.data));
                    },
                )
                .catch(handleError);
    }, [setSway]);

    if (!user) {
        return (
            <div>
                <p>Could not get your Sway. Are you logged in?</p>
            </div>
        );
    }

    if (isEmptyObject(sways)) {
        return <FullWindowLoading message={"Loading Your Sway..."} />;
    }

    return (
        <>
            {sways.map((s: IResponseData) => {
                return (
                    <div
                        key={s.locale.name}
                        style={{
                            width: "80%",
                            margin: "50px auto",
                        }}
                    >
                        <div className={"inline"}>
                            <Avatar
                                src={`/avatars/${s.locale.name}.svg`}
                                alt={s.locale.city}
                            />
                            <h2 style={{ marginLeft: 5 }}>
                                {toFormattedLocaleName(s.locale.name, false)}
                            </h2>
                        </div>
                        <Paper elevation={3}>
                            <div className={classes.container}>
                                <div className={classes.subcontainer}>
                                    <GridItem text={"Votes"} />
                                    <GridItem text={"Invitations Sent"} />
                                    <GridItem text={"Invitations Redeemed"} />
                                    <GridItem text={"Bills Shared"} />
                                    <GridItem text={"Total Shares"} />
                                    <GridItem Icon={Twitter} />
                                    <GridItem Icon={Facebook} />
                                    <GridItem Icon={WhatsApp} />
                                    <GridItem Icon={Telegram} />
                                </div>
                                <div className={classes.subcontainer}>
                                    <GridItem
                                        text={s.userSway.countBillsVotedOn}
                                    />
                                    <GridItem
                                        text={s.userSway.countInvitesSent}
                                    />
                                    <GridItem
                                        text={s.userSway.countInvitesRedeemed}
                                    />
                                    <GridItem
                                        text={s.userSway.countBillsShared}
                                    />
                                    <GridItem
                                        text={s.userSway.countAllBillShares}
                                    />
                                    <GridItem
                                        text={s.userSway.countTwitterShares}
                                    />
                                    <GridItem
                                        text={s.userSway.countFacebookShares}
                                    />
                                    <GridItem
                                        text={s.userSway.countWhatsappShares}
                                    />
                                    <GridItem
                                        text={s.userSway.countTelegramShares}
                                    />
                                </div>
                                <UserAwardsRow {...s} user={user} />
                            </div>
                        </Paper>
                    </div>
                );
            })}
        </>
    );
};

export default UserInfluence;
