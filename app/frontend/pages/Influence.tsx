import LocaleAvatar from "app/frontend/components/locales/LocaleAvatar";
import { useLocale } from "app/frontend/hooks/useLocales";
import { toFormattedLocaleName } from "app/frontend/sway_utils";
import { Fragment } from "react";
import { sway } from "sway";
import LocaleSelector from "../components/user/LocaleSelector";
import UserAwardsRow from "../components/user/awards/UserAwardsRow";
import { router } from "@inertiajs/react";

interface IProps {
    user: sway.IUser;
    influence: sway.IInfluence;
}

const _Influence: React.FC<IProps> = ({ influence }) => {
    const [locale] = useLocale();

    return (
        <div className="col">
            <LocaleSelector callback={() => router.reload()} />
            <Fragment key={locale.name}>
                <div className="row my-2">
                    <div className="col">
                        <div className="row my-2 align-items-center">
                            <div className="col-4">
                                <LocaleAvatar alt={locale.city} rounded thumbnail />
                            </div>
                            <div className="col ps-0">{toFormattedLocaleName(locale.name)}</div>
                        </div>
                        <div className="row">
                            <div className="row my-1 align-items-center">
                                <div className="col-1">&nbsp;</div>
                                <div className="col-6 bold">Votes:</div>
                                <div className="col-4 text-center">{influence?.countBillsVotedOn ?? 0}</div>
                            </div>
                            <div className="row my-1 align-items-center">
                                <div className="col-1">&nbsp;</div>
                                <div className="col-6 bold">Invitations Redeemed:</div>
                                <div className="col-4 text-center">{influence?.countInvitesRedeemed ?? 0}</div>
                            </div>
                            {/* <div className="row my-1 align-items-center">
                                <div className="col-1">&nbsp;</div>
                                <div className="col-6 bold">Bills Shared:</div>
                                <div className="col-4 text-center">{influence?.countBillsShared ?? 0}</div>
                            </div>
                            <div className="row my-1 align-items-center">
                                <div className="col-1">&nbsp;</div>
                                <div className="col-6 bold">Total Shares:</div>
                                <div className="col-4 text-center">{influence?.countAllBillShares ?? 0}</div>
                            </div> */}
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
                                {influence ? null : <div className="col-4 text-center">None</div>}
                            </div>
                        </div>
                    </div>
                </div>
            </Fragment>
        </div>
    );
};

// const Influence = SetupPage(_Influence);
const Influence = _Influence;
export default Influence;
