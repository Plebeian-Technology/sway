import { CLOUD_FUNCTIONS } from "@sway/constants";
import { isEmptyObject, logDev, toFormattedLocaleName } from "@sway/utils";
import { httpsCallable } from "firebase/functions";
import { Fragment, useEffect, useState } from "react";
import { Image } from "react-bootstrap";
import { sway } from "sway";
import { functions } from "../../firebase";
import { useUser } from "../../hooks";
import { useCancellable } from "../../hooks/cancellable";
import { handleError } from "../../utils";
import FullScreenLoading from "../dialogs/FullScreenLoading";
import UserAwardsRow from "./awards/UserAwardsRow";

interface IResponseData {
    locale: sway.IUserLocale;
    userSway: sway.IUserSway;
    localeSway: sway.IUserSway;
}

const UserSwayInfluence: React.FC = () => {
    const makeCancellable = useCancellable();
    const user = useUser();
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
                    }).catch(console.error);
                }),
            ),
            () => logDev("UserSwayInfluence.useEffect - canceled get influence."),
        );
        promise
            .then((responses: (firebase.default.functions.HttpsCallableResult | void)[]) => {
                setSway(
                    (
                        responses.filter(
                            Boolean,
                        ) as firebase.default.functions.HttpsCallableResult[]
                    ).map((r) => r.data),
                );
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
        return <FullScreenLoading message={"Loading Your Sway..."} />;
    }

    return (
        <>
            {sways.map((s: IResponseData, index: number) => {
                return (
                    <Fragment key={s.locale.name}>
                        <div className="row my-2">
                            <div className="col">
                                <div className="row my-2 align-items-center">
                                    <div className="col-3">
                                        <Image
                                            src={`/avatars/${s.locale.name}.svg`}
                                            alt={s.locale.city}
                                            rounded
                                            thumbnail
                                            className="border-0"
                                        />
                                    </div>
                                    <div className="col ps-0">
                                        {toFormattedLocaleName(s.locale.name, false)}
                                    </div>
                                </div>
                                <div className="row">
                                    <div className="row my-1 align-items-center">
                                        <div className="col-1">&nbsp;</div>
                                        <div className="col-6 bold">Votes:</div>
                                        <div className="col-4 text-center">
                                            {s.userSway.countBillsVotedOn}
                                        </div>
                                    </div>
                                    <div className="row my-1 align-items-center">
                                        <div className="col-1">&nbsp;</div>
                                        <div className="col-6 bold">Invitations Sent:</div>
                                        <div className="col-4 text-center">
                                            {s.userSway.countInvitesSent}
                                        </div>
                                    </div>
                                    <div className="row my-1 align-items-center">
                                        <div className="col-1">&nbsp;</div>
                                        <div className="col-6 bold">Invitations Redeemed:</div>
                                        <div className="col-4 text-center">
                                            {s.userSway.countInvitesRedeemed}
                                        </div>
                                    </div>
                                    <div className="row my-1 align-items-center">
                                        <div className="col-1">&nbsp;</div>
                                        <div className="col-6 bold">Bills Shared:</div>
                                        <div className="col-4 text-center">
                                            {s.userSway.countBillsShared}
                                        </div>
                                    </div>
                                    <div className="row my-1 align-items-center">
                                        <div className="col-1">&nbsp;</div>
                                        <div className="col-6 bold">Total Shares:</div>
                                        <div className="col-4 text-center">
                                            {s.userSway.countAllBillShares}
                                        </div>
                                    </div>
                                    {/* <div className="row my-1 align-items-center">
                                        <div className="col-1">&nbsp;</div>
                                        <div className="col-6 bold">Shares by Network:</div>
                                    </div> */}
                                    {/* <div className="row align-items-center my-1">
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
                                </div> */}
                                    <div className="row align-items-center my-1">
                                        <div className="col-1">&nbsp;</div>
                                        <div className="col-9">
                                            <div className="bold mb-2">Awards:</div>
                                            <UserAwardsRow {...s} user={user} />
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                        {index !== sways.length - 1 && (
                            <div className="row">
                                <div className="col-1">&nbsp;</div>
                                <div className="col-7 ms-3">
                                    <hr />
                                </div>
                            </div>
                        )}
                    </Fragment>
                );
            })}
        </>
    );
};

export default UserSwayInfluence;
