import { CONGRESS_LOCALE_NAME } from "@sway/constants";
import { titleize } from "@sway/utils";
import { useMemo } from "react";
import { Button, Modal } from "react-bootstrap";
import { SocialIcon } from "react-social-icons";
import { sway } from "sway";
import { useUser } from "../../hooks";
import { GAINED_SWAY_MESSAGE, handleError, notify, swayFireClient, withTadas } from "../../utils";
import EmailLegislatorShareButton from "./EmailLegislatorShareButton";
import InviteDialogShareButton from "./InviteDialogShareButton";

interface IProps {
    bill: sway.IBill;
    locale: sway.ILocale;
    userVote?: sway.IUserVote;
    handleClose: () => void;
    isOpen: boolean;
}

const ShareDialog: React.FC<IProps> = ({ bill, locale, userVote, handleClose, isOpen }) => {
    const user = useUser();
    const { name, city } = locale;

    const hashtag = name === CONGRESS_LOCALE_NAME ? "SwayCongres" : `Sway${titleize(city)}`;
    const message = `I voted on the Sway ${titleize(locale.city)} bill of the week, ${
        bill.externalId
    }. Will you sway with me?`;
    const tweet = `I voted on the Sway ${titleize(locale.city)} bill of the week, ${
        bill.externalId
    }. Will you #sway with me?`;
    const url = "https://app.sway.vote/bill-of-the-week";

    const handleShared = (platform: sway.TSharePlatform) => {
        const userLocale = user.locales.find((l: sway.IUserLocale) => l.name === locale.name);
        const fireClient = swayFireClient(userLocale);

        fireClient
            .userBillShares(user.uid)
            .update({
                billFirestoreId: bill.firestoreId,
                platform,
                uid: user.uid,
            })
            .then(() => {
                notify({
                    level: "success",
                    title: "Thanks for sharing!",
                    message: withTadas(GAINED_SWAY_MESSAGE),
                    tada: true,
                });
            })
            .catch(handleError);
    };

    const open = (route: string, platform: sway.TSharePlatform) => () => {
        window.open(route, "_blank");
        handleShared(platform);
    };

    const items = useMemo(
        () => [
            {
                network: "facebook",
                url: `https://www.facebook.com/sharer/sharer.php?u=${url}&quote=${message}&hashtag=${hashtag}`,
            },
            {
                network: "whatsapp",
                url: `https://api.whatsapp.com/send?text=${message} ${url}`,
            },
            {
                network: "twitter",
                url: `https://twitter.com/intent/tweet?text=${tweet}&url=${url}&text=${tweet}&hasttags=${JSON.stringify(
                    [hashtag],
                )}`,
            },
            {
                network: "reddit",
                url: `https://www.reddit.com/submit?url=${url}&title=${message}`,
            },
            {
                network: "linkedin",
                url: `https://www.linkedin.com/shareArticle?mini=true&url=${url}&title=${message}&source=https://app.sway.vote`,
            },
            {
                network: "pintrest",
                url: `http://pinterest.com/pin/create/link/?url=${url}&description=${message}`,
            },
            {
                network: "telegram",
                url: `https://t.me/share/url?url=${url}&text=${message}`,
            },
        ],
        [url, message, hashtag, tweet],
    ) as { network: sway.TSharePlatform; url: string }[];

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
                            onClick={() => open(i.url, i.network)}
                        >
                            <SocialIcon
                                url={i.url}
                                onClick={() => open(i.url, i.network)}
                                target="_blank"
                            />
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
