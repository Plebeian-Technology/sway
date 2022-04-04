import { Avatar, Theme, Typography } from "@mui/material";
import { makeStyles } from "@mui/styles";
import Paper from "@mui/material/Paper";
import { Facebook, Telegram, Twitter, WhatsApp } from "@mui/icons-material";
import { CLOUD_FUNCTIONS } from "@sway/constants";
import { isEmptyObject, logDev, toFormattedLocaleName } from "@sway/utils";
import { useEffect, useState } from "react";
import { sway } from "sway";
import { functions } from "../../firebase";
import { handleError, IS_MOBILE_PHONE } from "../../utils";
import FullWindowLoading from "../dialogs/FullWindowLoading";
import { TMuiIcon } from "../SwaySvg";
import UserAwardsRow from "./awards/UserAwardsRow";
import { useCancellable } from "../../hooks/cancellable";

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
    return {
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
    };
});

const GridItem = ({
    text,
    Icon,
}: {
    text?: string | number;
    Icon?: TMuiIcon;
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
    const makeCancellable = useCancellable();
    const [sways, setSway] = useState<IResponseData[]>([]);

    useEffect(() => {
        if (!user?.locales) {
            logDev(
                "UserInfluence.useEffect - no user.locales, skip getting influence.",
            );
            return;
        }
        const promise = makeCancellable(
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
            ),
            () => logDev("UserInfluence.useEffect - canceled get influence."),
        );
        promise
            .then(
                (
                    responses: firebase.default.functions.HttpsCallableResult[],
                ) => {
                    setSway(responses.map((r) => r.data));
                },
            )
            .catch(handleError);
    }, [!!user?.locales]);

    if (!user) {
        return (
            <div>
                <Typography>
                    Could not get your Sway. Are you logged in?
                </Typography>
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
