import { Avatar, Grid, Typography } from "@material-ui/core";
import Paper from "@material-ui/core/Paper";
import { Facebook, Telegram, Twitter, WhatsApp } from "@material-ui/icons";
import { CLOUD_FUNCTIONS } from "@sway/constants";
import { isEmptyObject, toFormattedLocaleName } from "@sway/utils";
import React, { useEffect, useState } from "react";
import { sway } from "sway";
import { functions } from "../../firebase";
import { handleError } from "../../utils";
import FullWindowLoading from "../dialogs/FullWindowLoading";
import { TSwaySvg } from "../SwaySvg";
import UserAwardsRow from "./UserAwardsRow";

interface IProps {
    user: sway.IUser | undefined;
}

interface IResponseData {
    locale: sway.IUserLocale;
    userSway: sway.IUserSway;
    localeSway: sway.IUserSway;
}

const GridItem = ({ text, style, Icon }: { text?: string | number; style?: sway.IPlainObject, Icon?: TSwaySvg }) => {
    if (text !== undefined) {
        return (
            <Grid item md zeroMinWidth>
                <div style={{
                    padding: 5,
                    ...style,
                }}>
                    <Typography>{text}</Typography>
                </div>
            </Grid>
        );
    }
    if (Icon) {
        return (
            <Grid item md zeroMinWidth>
                <div style={{
                    padding: 5,
                    ...style,
                }}>
                    <Icon />
                </div>
            </Grid>
        );
    }
    return null;
};

const UserInfluence: React.FC<IProps> = ({ user }) => {
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

    console.log({ sways });

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
                        <Paper elevation={2}>
                            <Grid container direction="column" justify="center" alignItems="center">
                                <Grid container direction="row" spacing={1} justify="center" alignItems="center">
                                    <GridItem text={"Votes"} style={{ paddingLeft: 15 }} />
                                    <GridItem text={"Invitations Used"} />
                                    <GridItem text={"Bills Shared"} />
                                    <GridItem text={"Total Shares"} />
                                    <GridItem Icon={Twitter} />
                                    <GridItem Icon={Facebook} />
                                    <GridItem Icon={WhatsApp} />
                                    <GridItem Icon={Telegram} />
                                </Grid>
                                <Grid container direction="row" spacing={1} justify="center" alignItems="center">
                                    <GridItem
                                        style={{ paddingLeft: 15 }}
                                        text={s.userSway.countBillsVotedOn}
                                    />
                                    <GridItem
                                        text={s.userSway.countInvitesUsed}
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
                                </Grid>
                            </Grid>
                            <UserAwardsRow {...s} user={user} />
                        </Paper>
                    </div>
                );
            })}
        </>
    );
};

export default UserInfluence;
