import { Typography } from "@material-ui/core";
import { AWARD_TYPES, CONGRESS_LOCALE_NAME } from "@sway/constants";
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
import { useUserSettings } from "../../hooks";
import { useCongratulations } from "../../hooks/awards";
import {
    handleError,
    IS_FIREFOX,
    IS_MOBILE_PHONE,
    swayFireClient,
    SWAY_COLORS,
} from "../../utils";
import CenteredDivRow from "../shared/CenteredDivRow";
import Award from "../user/awards/Award";
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
    const settings = useUserSettings();
    const [isCongratulations, setIsCongratulations] = useCongratulations();

    const handleShared = (platform: ESocial) => {
        const userLocale = user.locales.find(
            (l: sway.IUserLocale) => l.name === locale.name,
        );
        const fireClient = swayFireClient(userLocale);
        IS_DEVELOPMENT && console.log("(dev) Upserting user share data");

        fireClient
            .userBillShares(user.uid)
            .update({
                billFirestoreId: bill.firestoreId,
                platform,
                uid: user.uid,
            })
            .then(() => {
                IS_DEVELOPMENT && console.log("(dev) Set congratulations");
                setIsCongratulations(
                    settings?.congratulations?.isCongratulateOnSocialShare ===
                        undefined
                        ? true
                        : settings?.congratulations
                              ?.isCongratulateOnSocialShare,
                );
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
            <Typography>Increase your sway by encouraging people you know to vote.</Typography>
            <CenteredDivRow style={{ flexWrap: "wrap" }}>
                {IS_FIREFOX && IS_MOBILE_PHONE ? null : (
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
                {userVote && (
                    <EmailLegislatorShareButton
                    user={user}
                    locale={locale}
                    userVote={userVote}
                    />
                    )}
                <InviteIconDialogShareButton user={user} iconStyle={{ color: SWAY_COLORS.white }} />
            </CenteredDivRow>
            {isCongratulations && (
                <Award
                    user={user}
                    locale={locale}
                    type={AWARD_TYPES.BillShare}
                    setIsCongratulations={setIsCongratulations}
                />
            )}
        </div>
    );
};

export default ShareButtons;
