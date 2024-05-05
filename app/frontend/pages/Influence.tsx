import { useLocale } from "app/frontend/hooks/useLocales";
import { toFormattedLocaleName } from "app/frontend/sway_utils";
import { Fragment, useState } from "react";
import { Image } from "react-bootstrap";
import { sway } from "sway";
import CenteredLoading from "../components/dialogs/CenteredLoading";
import LocaleSelector from "../components/user/LocaleSelector";
import UserAwardsRow from "../components/user/awards/UserAwardsRow";
import SwaySvg from "app/frontend/components/SwaySvg";
import SwayLogo from "app/frontend/components/SwayLogo";

const Influence: React.FC = () => {
    const [locale] = useLocale();
    const [influence, setInfluence] = useState<sway.IUserSway | undefined>();
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
                <Fragment key={locale.name}>
                    <div className="row my-2">
                        <div className="col">
                            <div className="row my-2 align-items-center">
                                <div className="col-3">
                                    <Image
                                        src={`/assets/avatars/${locale.name}.svg`}
                                        alt={locale.city}
                                        rounded
                                        thumbnail
                                        className="border-0"
                                    />
                                </div>
                                <div className="col ps-0">
                                    {toFormattedLocaleName(locale.name, false)}
                                </div>
                            </div>
                            <div className="row">
                                <div className="row my-1 align-items-center">
                                    <div className="col-1">&nbsp;</div>
                                    <div className="col-6 bold">Votes:</div>
                                    <div className="col-4 text-center">
                                        {influence?.countBillsVotedOn ?? 0}
                                    </div>
                                </div>
                                <div className="row my-1 align-items-center">
                                    <div className="col-1">&nbsp;</div>
                                    <div className="col-6 bold">Invitations Sent:</div>
                                    <div className="col-4 text-center">
                                        {influence?.countInvitesSent ?? 0}
                                    </div>
                                </div>
                                <div className="row my-1 align-items-center">
                                    <div className="col-1">&nbsp;</div>
                                    <div className="col-6 bold">Invitations Redeemed:</div>
                                    <div className="col-4 text-center">
                                        {influence?.countInvitesRedeemed ?? 0}
                                    </div>
                                </div>
                                <div className="row my-1 align-items-center">
                                    <div className="col-1">&nbsp;</div>
                                    <div className="col-6 bold">Bills Shared:</div>
                                    <div className="col-4 text-center">
                                        {influence?.countBillsShared ?? 0}
                                    </div>
                                </div>
                                <div className="row my-1 align-items-center">
                                    <div className="col-1">&nbsp;</div>
                                    <div className="col-6 bold">Total Shares:</div>
                                    <div className="col-4 text-center">
                                        {influence?.countAllBillShares ?? 0}
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
                                        {influence?.countTwitterShares ?? 0 || 0}
                                    </div>
                                    <div className="col-1">
                                        <FaFacebook size="1.5em" color={SWAY_COLORS.primary} />
                                    </div>
                                    <div className="col-1">
                                        {influence?.countFacebookShares ?? 0 || 0}
                                    </div>
                                    <div className="col-1">
                                        <FaWhatsapp size="1.5em" color={SWAY_COLORS.primary} />
                                    </div>
                                    <div className="col-1">
                                        {influence?.countWhatsappShares ?? 0 || 0}
                                    </div>
                                    <div className="col-1">
                                        <FaTelegram size="1.5em" color={SWAY_COLORS.primary} />
                                    </div>
                                    <div className="col-1">
                                        {influence?.countTelegramShares ?? 0 || 0}
                                    </div>
                                    <div className="col-1">
                                        <FiMail size="1.5em" color={SWAY_COLORS.primary} />
                                    </div>
                                    <div className="col-1">{influence?.countEmailShares ?? 0 || 0}</div>
                                </div> */}
                                <div className="row align-items-center my-1">
                                    <div className="col-1">&nbsp;</div>
                                    <div className={influence ? "col-9" : "col-6"}>
                                        <div className="bold mb-2">Awards:</div>
                                        {influence && <UserAwardsRow influence={influence} />}
                                    </div>
                                    {influence ? null : <div className="col-4 text-center">
                                        None
                                    </div>}
                                </div>
                            </div>
                        </div>
                        <div className="text-center py-5">
                        <SwayLogo />
                        </div>
                    </div>
                </Fragment>

        </div>
    );
};

export default Influence;
