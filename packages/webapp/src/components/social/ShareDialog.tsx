import { Dialog, DialogTitle, DialogContent, DialogActions, Button } from "@mui/material";
import { CONGRESS_LOCALE_NAME } from "@sway/constants";
import { logDev, titleize } from "@sway/utils";
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
    withTadas,
} from "../../utils";
import EmailLegislatorShareButton from "./EmailLegislatorShareButton";
import InviteDialogShareButton from "./InviteDialogShareButton";

interface IProps {
    bill: sway.IBill;
    locale: sway.ILocale;
    user: sway.IUser;
    userVote?: sway.IUserVote;
    handleClose: () => void;
}

enum ESocial {
    Email = "email",
    Twitter = "twitter",
    Facebook = "facebook",
    WhatsApp = "whatsapp",
    Telegram = "telegram",
}

const ShareDialog: React.FC<IProps> = ({ bill, locale, user, userVote, handleClose }) => {
    const { name, city } = locale;

    const hashtag = name === CONGRESS_LOCALE_NAME ? "SwayCongres" : `Sway${titleize(city)}`;

    const message = "I voted on the Sway bill of the week. Will you sway with me?";
    const tweet = "I voted on the Sway bill of the week. Will you #sway with me?";
    const url = "https://app.sway.vote/bill-of-the-week";

    const handleShared = (platform: ESocial) => {
        const userLocale = user.locales.find((l: sway.IUserLocale) => l.name === locale.name);
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

    return (
        <Dialog
            open={true}
            onClose={handleClose}
            aria-labelledby="alert-dialog-title"
            aria-describedby="alert-dialog-description"
        >
            <DialogTitle id="alert-dialog-title">
                Earn Sway by sharing your actions or inviting friends.
            </DialogTitle>
            <DialogContent className="pointer">
                <div className="row justify-content-center">
                    {IS_FIREFOX && IS_MOBILE_PHONE ? null : (
                        <>
                            <div className="col p-3">
                                <TwitterShareButton
                                    id={"twitter-share-button"}
                                    url={url}
                                    title={tweet}
                                    hashtags={[hashtag]}
                                    windowWidth={900}
                                    windowHeight={900}
                                    onShareWindowClose={() => handleShared(ESocial.Twitter)}
                                >
                                    <TwitterIcon />
                                </TwitterShareButton>
                            </div>
                            <div className="col p-3">
                                <FacebookShareButton
                                    id={"facebook-share-button"}
                                    url={url}
                                    quote={message}
                                    hashtag={hashtag}
                                    windowWidth={900}
                                    windowHeight={900}
                                    onShareWindowClose={() => handleShared(ESocial.Facebook)}
                                >
                                    <FacebookIcon />
                                </FacebookShareButton>
                            </div>
                        </>
                    )}
                    <div className="col p-3">
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
                    </div>

                    <div className="col p-3">
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
                    </div>
                    {userVote && (
                        <div className="col p-3">
                            <EmailLegislatorShareButton
                                user={user}
                                locale={locale}
                                userVote={userVote}
                            />
                        </div>
                    )}
                    <div className="col p-3">
                        <InviteDialogShareButton user={user} />
                    </div>
                </div>
            </DialogContent>
            <DialogActions>
                <Button onClick={handleClose} color="primary">
                    Close
                </Button>
            </DialogActions>
        </Dialog>
    );
};

export default ShareDialog;
