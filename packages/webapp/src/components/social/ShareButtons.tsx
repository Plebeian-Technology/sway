import { CONGRESS_LOCALE_NAME } from "@sway/constants";
import { IS_DEVELOPMENT, titleize } from "@sway/utils";
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
    handleError,
    isMobilePhone,
    IS_FIREFOX,
    swayFireClient,
} from "../../utils";
import CenteredDivRow from "../shared/CenteredDivRow";
import InviteIconDialogShareButton from "./InviteDialogShareButton";

interface IProps {
    bill: sway.IBill;
    locale: sway.ILocale;
    user: sway.IUser;
}

enum ESocial {
    Email = "email",
    Twitter = "twitter",
    Facebook = "facebook",
    WhatsApp = "whatsapp",
    Telegram = "telegram",
}

const ShareButtons: React.FC<IProps> = ({ bill, locale, user }) => {
    const handleShared = (platform: ESocial) => {
        const userLocale = user.locales.find(
            (l: sway.IUserLocale) => l.name === locale.name,
        );
        const fireClient = swayFireClient(userLocale);
        IS_DEVELOPMENT && console.log("Upserting user share data (dev)");

        fireClient
            .userBillShares(user.uid)
            .update({
                billFirestoreId: bill.firestoreId,
                platform,
                uid: user.uid,
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
            <p>Increase your sway by encouraging people you know to vote.</p>
            <CenteredDivRow>
                {IS_FIREFOX && isMobilePhone ? null : (
                    <>
                        <TwitterShareButton
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
                    url={url}
                    title={message}
                    windowWidth={900}
                    windowHeight={900}
                    onShareWindowClose={() => handleShared(ESocial.WhatsApp)}
                >
                    <WhatsappIcon />
                </WhatsappShareButton>
                <TelegramShareButton
                    url={url}
                    title={message}
                    windowWidth={900}
                    windowHeight={900}
                    onShareWindowClose={() => handleShared(ESocial.Telegram)}
                >
                    <TelegramIcon />
                </TelegramShareButton>
                <InviteIconDialogShareButton user={user} />
            </CenteredDivRow>
        </div>
    );
};

export default ShareButtons;
