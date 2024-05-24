import { CONGRESS_LOCALE_NAME } from "app/frontend/sway_constants";
import { titleize } from "app/frontend/sway_utils";
import { useCallback, useMemo } from "react";
import { Button, Modal } from "react-bootstrap";
import { SocialIcon } from "react-social-icons";
import { sway } from "sway";
import { useUser } from "../../hooks/users/useUser";

import InviteDialogShareButton from "./InviteDialogShareButton";
import InviteBody from "app/frontend/components/dialogs/invites/InviteBody";
import ButtonUnstyled from "app/frontend/components/ButtonUnstyled";

interface IProps {
    bill: sway.IBill;
    locale: sway.ISwayLocale;
    userVote?: sway.IUserVote;
    handleClose: () => void;
    isOpen: boolean;
}

const url = "https://app.sway.vote/bill_of_the_week";

const ShareDialog: React.FC<IProps> = ({ bill, locale, userVote, handleClose, isOpen }) => {
    const user = useUser();
    const { name, city } = locale;

    const hashtag = useMemo(
        () => (name === CONGRESS_LOCALE_NAME ? "SwayCongres" : `Sway${titleize(city)}`),
        [name, city],
    );

    const message = useMemo(
        () => `I voted on the Sway ${titleize(city)} Bill of the Week, ${bill.externalId}.`,
        [city, bill.externalId],
    );
    const tweet = useMemo(
        () => `I voted on the Sway ${titleize(city)} bill of the week, ${bill.externalId}.`,
        [city, bill.externalId],
    );


    const open = useCallback(
        (route: string) => () => {
            window.open(route, "_blank");
        },
        [],
    );

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
        [message, hashtag, tweet],
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
                        <ButtonUnstyled key={i.url} className="col-4 text-center my-3" onClick={() => open(i.url)}>
                            <SocialIcon url={i.url} onClick={() => open(i.url)} target="_blank" />
                        </ButtonUnstyled>
                    ))}
                </div>
                <hr />
                <div className="row my-3">
                    <div className="col">
                        <InviteBody />
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
