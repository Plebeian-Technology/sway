import { Facebook, Telegram, Twitter, WhatsApp } from "@mui/icons-material";
import { Avatar, Divider, Typography } from "@mui/material";
import Paper from "@mui/material/Paper";
import { CLOUD_FUNCTIONS } from "@sway/constants";
import { isEmptyObject, logDev, toFormattedLocaleName } from "@sway/utils";
import { httpsCallable } from "firebase/functions";
import { useEffect, useState } from "react";
import { sway } from "sway";
import { functions } from "../../firebase";
import { useCancellable } from "../../hooks/cancellable";
import { handleError } from "../../utils";
import FullWindowLoading from "../dialogs/FullWindowLoading";
import UserAwardsRow from "./awards/UserAwardsRow";

interface IProps {
    user: sway.IUser | undefined;
}

interface IResponseData {
    locale: sway.IUserLocale;
    userSway: sway.IUserSway;
    localeSway: sway.IUserSway;
}

const UserSwayInfluence: React.FC<IProps> = ({ user }) => {
    const makeCancellable = useCancellable();
    const [sways, setSway] = useState<IResponseData[]>([]);

    useEffect(() => {
        if (!user?.locales) {
            logDev("UserSwayInfluence.useEffect - no user.locales, skip getting influence.");
            return;
        }
        const promise = makeCancellable(
            Promise.all(
                user.locales.map((userLocale: sway.IUserLocale) => {
                    const getter = httpsCallable(functions, CLOUD_FUNCTIONS.getUserSway);
                    return getter({
                        uid: user.uid,
                        locale: userLocale,
                    });
                }),
            ),
            () => logDev("UserSwayInfluence.useEffect - canceled get influence."),
        );
        promise
            .then((responses: firebase.default.functions.HttpsCallableResult[]) => {
                setSway(responses.map((r) => r.data));
            })
            .catch(handleError);
    }, [!!user?.locales]);

    if (!user) {
        return (
            <div>
                <Typography>Could not get your Sway. Are you logged in?</Typography>
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
                    <div key={s.locale.name} className="row my-2">
                        <div className="col">
                            <div
                                className="row g-0 my-2 align-items-center"
                                style={{ maxWidth: 300 }}
                            >
                                <div className="col-2">
                                    <Avatar
                                        src={`/avatars/${s.locale.name}.svg`}
                                        alt={s.locale.city}
                                    />
                                </div>
                                <div className="col">
                                    {toFormattedLocaleName(s.locale.name, false)}
                                </div>
                            </div>
                            <Paper elevation={3} className="row m-0 p-3">
                                <div className="col">
                                    <div className="row g-0 my-1">
                                        <span>
                                            <span className="bold">Votes:</span>&nbsp;
                                            {s.userSway.countBillsVotedOn}
                                        </span>
                                    </div>
                                    <div className="row g-0 my-1">
                                        <span>
                                            <span className="bold">Invitations Sent:</span>&nbsp;
                                            {s.userSway.countInvitesSent}
                                        </span>
                                    </div>
                                    <div className="row g-0 my-1">
                                        <span>
                                            <span className="bold">Invitations Redeemed:</span>
                                            &nbsp;
                                            {s.userSway.countInvitesRedeemed}
                                        </span>
                                    </div>
                                    <div className="row g-0 my-1">
                                        <span>
                                            <span className="bold">Bills Shared:</span>&nbsp;
                                            {s.userSway.countBillsShared}
                                        </span>
                                    </div>
                                    <div className="row g-0 my-1">
                                        <span>
                                            <span className="bold">Total Shares:</span>&nbsp;
                                            {s.userSway.countAllBillShares}
                                        </span>
                                    </div>
                                    <div className="row g-0 my-1">
                                        <Twitter />
                                        &nbsp;{s.userSway.countTwitterShares}
                                    </div>
                                    <div className="row g-0 my-1">
                                        <Facebook />
                                        &nbsp;{s.userSway.countFacebookShares}
                                    </div>
                                    <div className="row g-0 my-1">
                                        <WhatsApp />
                                        &nbsp;{s.userSway.countWhatsappShares}
                                    </div>
                                    <div className="row g-0 my-1">
                                        <Telegram />
                                        &nbsp;{s.userSway.countTelegramShares}
                                    </div>
                                    <Divider className="my-3" />
                                    <div className="row g-0 my-3">
                                        <span className="bold my-1">Awards</span>
                                        <UserAwardsRow {...s} user={user} />
                                    </div>
                                </div>
                            </Paper>
                        </div>
                    </div>
                );
            })}
        </>
    );
};

export default UserSwayInfluence;
