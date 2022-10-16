import { CONGRESS_LOCALE_NAME } from "@sway/constants";
import { titleize } from "@sway/utils";
import { useMemo } from "react";
import { Button, Modal } from "react-bootstrap";
import { SocialIcon } from "react-social-icons";
import { sway } from "sway";
import EmailLegislatorShareButton from "./EmailLegislatorShareButton";
import InviteDialogShareButton from "./InviteDialogShareButton";

interface IProps {
    bill: sway.IBill;
    locale: sway.ILocale;
    user: sway.IUser;
    userVote?: sway.IUserVote;
    handleClose: () => void;
    isOpen: boolean;
}

// eslint-disable-next-line
enum ESocial {
    Email = "email",
    Twitter = "twitter",
    Facebook = "facebook",
    WhatsApp = "whatsapp",
    LinkedIn = "linkedin",
    Telegram = "telegram",
    Reddit = "reddit",
    Pintrest = "pinterest",
}

const ShareDialog: React.FC<IProps> = ({ bill, locale, user, userVote, handleClose, isOpen }) => {
    const { name, city } = locale;

    const hashtag = name === CONGRESS_LOCALE_NAME ? "SwayCongres" : `Sway${titleize(city)}`;
    const message = `I voted on the Sway ${titleize(locale.city)} bill of the week, ${
        bill.externalId
    }. Will you sway with me?`;
    const tweet = `I voted on the Sway ${titleize(locale.city)} bill of the week, ${
        bill.externalId
    }. Will you #sway with me?`;
    const url = "https://app.sway.vote/bill-of-the-week";

    const open = (route: string) => () => window.open(route, "_blank");

    const items = useMemo(
        () => [
            {
                network: ESocial.Facebook,
                url: `https://www.facebook.com/sharer/sharer.php?u=${url}&quote=${message}&hashtag=${hashtag}`,
            },
            {
                network: ESocial.WhatsApp,
                url: `https://api.whatsapp.com/send?text=${message} ${url}`,
                // url: getShareUrl(SocialPlatforms.WhatsApp, {
                //     url,
                //     text: message,
                // }),
            },
            {
                network: ESocial.Twitter,
                url: `https://twitter.com/intent/tweet?text=${tweet}&url=${url}&text=${tweet}&hasttags=${JSON.stringify(
                    [hashtag],
                )}`,
            },
            {
                network: ESocial.Reddit,
                url: `https://www.reddit.com/submit?url=${url}&title=${message}`,
            },
            {
                network: ESocial.LinkedIn,
                url: `https://www.linkedin.com/shareArticle?mini=true&url=${url}&title=${message}&source=https://app.sway.vote`,
            },
            {
                network: ESocial.Pintrest,
                url: `http://pinterest.com/pin/create/link/?url=${url}&description=${message}`,
            },
            {
                network: ESocial.Telegram,
                url: `https://t.me/share/url?url=${url}&text=${message}`,
            },
        ],
        [url, message, hashtag, tweet],
    );

    return (
        <Modal centered show={isOpen} aria-labelledby="share-buttons-dialog" onHide={handleClose}>
            <Modal.Header>
                <Modal.Title id="share-buttons-dialog">
                    Earn Sway by sharing the votes you make or by inviting friends.
                </Modal.Title>
            </Modal.Header>
            <Modal.Body className="pointer">
                <div className="row align-items-center">
                    {items.map((i) => (
                        <div
                            key={i.url}
                            className="col-4 text-center mx-auto my-3"
                            onClick={() => open(i.url)}
                        >
                            <SocialIcon url={i.url} onClick={() => open(i.url)} target="_blank" />
                        </div>
                    ))}

                    {userVote && (
                        <div className="col-4 text-center my-3">
                            <EmailLegislatorShareButton
                                user={user}
                                locale={locale}
                                userVote={userVote}
                                className="text-center mx-auto rounded-circle m-0 border-0"
                                iconStyle={{ width: 50, height: 50 }}
                            />
                        </div>
                    )}
                    <div className="col-4 text-center my-3">
                        <InviteDialogShareButton
                            user={user}
                            className="text-center mx-auto rounded-circle m-0 border-0"
                            iconStyle={{ width: 50, height: 50 }}
                        />
                    </div>
                </div>
            </Modal.Body>
            <Modal.Footer>
                <Button onClick={handleClose}>Close</Button>
            </Modal.Footer>
        </Modal>
    );
};

export default ShareDialog;
