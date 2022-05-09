import { CLOUD_FUNCTIONS } from "@sway/constants";
import { isEmptyObject, logDev, toFormattedLocaleName } from "@sway/utils";
import { httpsCallable } from "firebase/functions";
import { useEffect, useState } from "react";
import { Image } from "react-bootstrap";
import { FaFacebook, FaTelegram, FaTwitter, FaWhatsapp } from "react-icons/fa";
import { FiMail } from "react-icons/fi";
import { sway } from "sway";
import { functions } from "../../firebase";
import { useCancellable } from "../../hooks/cancellable";
import { handleError, SWAY_COLORS } from "../../utils";
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
                <span>Could not get your Sway. Are you logged in?</span>
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
                            <div className="row my-2 align-items-center">
                                <div className="col-3">
                                    <Image
                                        src={`/avatars/${s.locale.name}.svg`}
                                        alt={s.locale.city}
                                        rounded
                                        thumbnail
                                    />
                                </div>
                                <div className="col ps-0">
                                    {toFormattedLocaleName(s.locale.name, false)}
                                </div>
                            </div>
                            <div className="row">
                                <div className="row my-1 align-items-center">
                                    <div className="col-8 bold">Votes:</div>
                                    <div className="col-4">{s.userSway.countBillsVotedOn}</div>
                                </div>
                                <div className="row my-1 align-items-center">
                                    <div className="col-8 bold">Invitations Sent:</div>
                                    <div className="col-4">{s.userSway.countInvitesSent}</div>
                                </div>
                                <div className="row my-1 align-items-center">
                                    <div className="col-8 bold">Invitations Redeemed:</div>
                                    <div className="col-4">{s.userSway.countInvitesRedeemed}</div>
                                </div>
                                <div className="row my-1 align-items-center">
                                    <div className="col-8 bold">Bills Shared:</div>
                                    <div className="col-4">{s.userSway.countBillsShared}</div>
                                </div>
                                <div className="row my-1 align-items-center">
                                    <div className="col-8 bold">Total Shares:</div>
                                    <div className="col-4">{s.userSway.countAllBillShares}</div>
                                </div>
                                <div className="row my-1 align-items-center">
                                    <div className="col-8 bold">Shares by Network:</div>
                                </div>
                                <div className="row align-items-center my-1">
                                    <div className="col-1">
                                        <FaTwitter size="1.5em" color={SWAY_COLORS.primary} />
                                    </div>
                                    <div className="col-1">
                                        {s.userSway.countTwitterShares || 0}
                                    </div>
                                    <div className="col-1">
                                        <FaFacebook size="1.5em" color={SWAY_COLORS.primary} />
                                    </div>
                                    <div className="col-1">
                                        {s.userSway.countFacebookShares || 0}
                                    </div>
                                    <div className="col-1">
                                        <FaWhatsapp size="1.5em" color={SWAY_COLORS.primary} />
                                    </div>
                                    <div className="col-1">
                                        {s.userSway.countWhatsappShares || 0}
                                    </div>
                                    <div className="col-1">
                                        <FaTelegram size="1.5em" color={SWAY_COLORS.primary} />
                                    </div>
                                    <div className="col-1">
                                        {s.userSway.countTelegramShares || 0}
                                    </div>
                                    <div className="col-1">
                                        <FiMail size="1.5em" color={SWAY_COLORS.primary} />
                                    </div>
                                    <div className="col-1">{s.userSway.countEmailShares || 0}</div>
                                </div>
                                <div className="row align-items-center my-1">
                                    <div className="col">
                                        <div className="bold mb-2">Awards:</div>
                                        <UserAwardsRow {...s} user={user} />
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                );
            })}
        </>
    );
};

export default UserSwayInfluence;
