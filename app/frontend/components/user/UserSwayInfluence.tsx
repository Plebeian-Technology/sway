import { toFormattedLocaleName } from "app/frontend/sway_utils";
import { Fragment, useState } from "react";
import { Image } from "react-bootstrap";
import { sway } from "sway";
import { useCancellable } from "../../hooks/useCancellable";
import { useUserUid } from "../../hooks/users/useUserUid";
import CenteredLoading from "../dialogs/CenteredLoading";
import LocaleSelector from "./LocaleSelector";
import UserAwardsRow from "./awards/UserAwardsRow";

interface IResponseData {
    locale: sway.ISwayLocale;
    userSway: sway.IUserSway;
    localeSway: sway.IUserSway;
}

const UserSwayInfluence: React.FC = () => {
    const makeCancellable = useCancellable();
    const uid = useUserUid();
    const [influence, setInfluence] = useState<IResponseData | undefined>();
    const [isLoading, setLoading] = useState<boolean>(false);

    // useEffect(() => {
    //     if (!userLocale) {
    //         return;
    //     }

    //     setLoading(true);
    //     makeCancellable(
    //         getter({
    //             uid: uid,
    //             locale: userLocale,
    //         }),
    //     )
    //         .then((response: firebase.default.functions.HttpsCallableResult | void) => {
    //             setLoading(false);
    //             const result = response?.data;
    //             if (result) {
    //                 setInfluence(result);
    //             }
    //         })
    //         .catch((e) => {
    //             setLoading(false);
    //             handleError(e);
    //         });
    // }, [uid, userLocale, makeCancellable]);

    return (
        <div className="col">
            <LocaleSelector />
            {isLoading && <CenteredLoading message="Loading Sway..." className="mt-5" />}
            {!influence ? null : (
                <Fragment key={influence.locale.name}>
                    <div className="row my-2">
                        <div className="col">
                            <div className="row my-2 align-items-center">
                                <div className="col-3">
                                    <Image
                                        src={`/assets/avatars/${influence.locale.name}.svg`}
                                        alt={influence.locale.city}
                                        rounded
                                        thumbnail
                                        className="border-0"
                                    />
                                </div>
                                <div className="col ps-0">
                                    {toFormattedLocaleName(influence.locale.name, false)}
                                </div>
                            </div>
                            <div className="row">
                                <div className="row my-1 align-items-center">
                                    <div className="col-1">&nbsp;</div>
                                    <div className="col-6 bold">Votes:</div>
                                    <div className="col-4 text-center">
                                        {influence.userSway.countBillsVotedOn}
                                    </div>
                                </div>
                                <div className="row my-1 align-items-center">
                                    <div className="col-1">&nbsp;</div>
                                    <div className="col-6 bold">Invitations Sent:</div>
                                    <div className="col-4 text-center">
                                        {influence.userSway.countInvitesSent}
                                    </div>
                                </div>
                                <div className="row my-1 align-items-center">
                                    <div className="col-1">&nbsp;</div>
                                    <div className="col-6 bold">Invitations Redeemed:</div>
                                    <div className="col-4 text-center">
                                        {influence.userSway.countInvitesRedeemed}
                                    </div>
                                </div>
                                <div className="row my-1 align-items-center">
                                    <div className="col-1">&nbsp;</div>
                                    <div className="col-6 bold">Bills Shared:</div>
                                    <div className="col-4 text-center">
                                        {influence.userSway.countBillsShared}
                                    </div>
                                </div>
                                <div className="row my-1 align-items-center">
                                    <div className="col-1">&nbsp;</div>
                                    <div className="col-6 bold">Total Shares:</div>
                                    <div className="col-4 text-center">
                                        {influence.userSway.countAllBillShares}
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
                                        {influence.userSway.countTwitterShares || 0}
                                    </div>
                                    <div className="col-1">
                                        <FaFacebook size="1.5em" color={SWAY_COLORS.primary} />
                                    </div>
                                    <div className="col-1">
                                        {influence.userSway.countFacebookShares || 0}
                                    </div>
                                    <div className="col-1">
                                        <FaWhatsapp size="1.5em" color={SWAY_COLORS.primary} />
                                    </div>
                                    <div className="col-1">
                                        {influence.userSway.countWhatsappShares || 0}
                                    </div>
                                    <div className="col-1">
                                        <FaTelegram size="1.5em" color={SWAY_COLORS.primary} />
                                    </div>
                                    <div className="col-1">
                                        {influence.userSway.countTelegramShares || 0}
                                    </div>
                                    <div className="col-1">
                                        <FiMail size="1.5em" color={SWAY_COLORS.primary} />
                                    </div>
                                    <div className="col-1">{influence.userSway.countEmailShares || 0}</div>
                                </div> */}
                                <div className="row align-items-center my-1">
                                    <div className="col-1">&nbsp;</div>
                                    <div className="col-9">
                                        <div className="bold mb-2">Awards:</div>
                                        <UserAwardsRow {...influence} />
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </Fragment>
            )}
        </div>
    );
};

export default UserSwayInfluence;
