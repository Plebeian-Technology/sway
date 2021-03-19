import { Typography } from "@material-ui/core";
import { CONGRESS_LOCALE_NAME } from "@sway/constants";
import { logDev, titleize } from "@sway/utils";
import React from "react";
import {
    FacebookIcon,
    FacebookShareButton,
    TelegramIcon,
    TelegramShareButton,
    TwitterIcon,
    TwitterShareButton,
    WhatsappIcon,
    WhatsappShareButton,
} from "react-share";
import { sway } from "sway";
import {
    GAINED_SWAY_MESSAGE,
    handleError,
    IS_FIREFOX,
    IS_MOBILE_PHONE,
    notify,
    swayFireClient,
    SWAY_COLORS,
    withTadas,
} from "../../utils";
import CenteredDivRow from "../shared/CenteredDivRow";
import EmailLegislatorShareButton from "./EmailLegislatorShareButton";
import InviteIconDialogShareButton from "./InviteDialogShareButton";

interface IProps {
    bill: sway.IBill;
    locale: sway.ILocale;
    user: sway.IUser;
    userVote?: sway.IUserVote;
}

enum ESocial {
    Email = "email",
    Twitter = "twitter",
    Facebook = "facebook",
    WhatsApp = "whatsapp",
    Telegram = "telegram",
}

const ShareButtons: React.FC<IProps> = ({ bill, locale, user, userVote }) => {
    const handleShared = (platform: ESocial) => {
        const userLocale = user.locales.find(
            (l: sway.IUserLocale) => l.name === locale.name,
        );
        const fireClient = swayFireClient(userLocale);
        logDev("Upserting user share data");

        fireClient
            .userBillShares(user.uid)
            .update({
                billFirestoreId: bill.firestoreId,
                platform,
                uid: user.uid,
            })
            .then(() => {
                logDev("Set congratulations");
                notify({
                    level: "success",
                    title: "Thanks for sharing!",
                    message: withTadas(GAINED_SWAY_MESSAGE),
                    tada: true,
                });
            })
            .catch(handleError);
    };

    const { name, city } = locale;
    const hashtag =
        name === CONGRESS_LOCALE_NAME ? "SwayCongres" : `Sway${titleize(city)}`;

    const message =
        "I voted on the Sway bill of the week. Will you sway with me?";
    const tweet =
        "I voted on the Sway bill of the week. Will you #sway with me?";
    const url = "https://app.sway.vote/bill-of-the-week";

    return (
        <div className="share-button-container">
            <Typography>
                Increase your sway by encouraging people you know to vote.
            </Typography>
            <CenteredDivRow style={{ flexWrap: "wrap" }}>
                {IS_FIREFOX && IS_MOBILE_PHONE ? null : (
                    <>
                        <TwitterShareButton
                            id={"twitter-share-button"}
                            url={url}
                            title={tweet}
                            hashtags={[hashtag]}
                            windowWidth={900}
                            windowHeight={900}
                            onShareWindowClose={() =>
                                handleShared(ESocial.Twitter)
                            }
                        >
                            <TwitterIcon />
                        </TwitterShareButton>
                        <FacebookShareButton
                            id={"facebook-share-button"}
                            url={url}
                            quote={message}
                            hashtag={hashtag}
                            windowWidth={900}
                            windowHeight={900}
                            onShareWindowClose={() =>
                                handleShared(ESocial.Facebook)
                            }
                        >
                            <FacebookIcon />
                        </FacebookShareButton>
                    </>
                )}
                <WhatsappShareButton
                    id={"whatsapp-share-button"}
                    url={url}
                    title={message}
                    windowWidth={900}
                    windowHeight={900}
                    onShareWindowClose={() => handleShared(ESocial.WhatsApp)}
                >
                    <WhatsappIcon />
                </WhatsappShareButton>
                <TelegramShareButton
                    id={"telegram-share-button"}
                    url={url}
                    title={message}
                    windowWidth={900}
                    windowHeight={900}
                    onShareWindowClose={() => handleShared(ESocial.Telegram)}
                >
                    <TelegramIcon />
                </TelegramShareButton>
                {userVote && (
                    <EmailLegislatorShareButton
                        user={user}
                        locale={locale}
                        userVote={userVote}
                    />
                )}
                <InviteIconDialogShareButton
                    user={user}
                    iconStyle={{ color: SWAY_COLORS.white }}
                />
            </CenteredDivRow>
        </div>
    );
};

export default ShareButtons;
