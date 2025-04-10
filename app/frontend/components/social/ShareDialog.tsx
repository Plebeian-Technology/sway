import { CONGRESS_LOCALE_NAME } from "app/frontend/sway_constants";
import { notify, titleize } from "app/frontend/sway_utils";
import copy from "copy-to-clipboard";
import { useCallback, useMemo } from "react";
import { Button, Modal } from "react-bootstrap";
import { SocialIcon } from "react-social-icons";
import { sway } from "sway";

import { usePage } from "@inertiajs/react";
import ButtonUnstyled from "app/frontend/components/ButtonUnstyled";
import InviteDialogShareButton from "app/frontend/components/social/InviteDialogShareButton";
import { useLocale } from "app/frontend/hooks/useLocales";
import { FiCopy } from "react-icons/fi";

interface IProps {
    handleClose: () => void;
    isOpen: boolean;
}

const url = "https://sway.vote/bill_of_the_week";

const ShareDialog: React.FC<IProps> = ({ handleClose, isOpen }) => {
    const [locale] = useLocale();
    const bill = usePage().props.bill as sway.IBill;
    const user_vote = usePage().props.user_vote as sway.IUserVote | undefined;

    const { name, city } = locale;

    const hashtag = useMemo(
        () => (name === CONGRESS_LOCALE_NAME ? "SwayCongres" : `Sway${titleize(city)}`),
        [name, city],
    );

    const message = useMemo(
        () => `I voted on the Sway ${titleize(city)} Bill of the Week, ${bill.external_id}.`,
        [city, bill.external_id],
    );
    const tweet = useMemo(
        () => `I voted on the Sway ${titleize(city)} bill of the week, ${bill.external_id}.`,
        [city, bill.external_id],
    );

    const open = useCallback(
        (route: string) => () => {
            window.open(route, "_blank");
        },
        [],
    );

    const handleCopy = useCallback(() => {
        const href = new URL(window.location.href);
        href.searchParams.append("sway_locale_name", name);
        copy(href.toString(), {
            message: "Click to Copy",
            format: "text/plain",
            onCopy: () =>
                notify({
                    level: "info",
                    title: "Copied bill link to clipboard.",
                }),
        });
    }, [name]);

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
                url: `https://www.linkedin.com/shareArticle?mini=true&url=${url}&title=${message}&source=https://sway.vote`,
            },
            {
                network: "pintrest",
                url: `http://pinterest.com/pin/create/link/?url=${url}&description=${message}`,
            },
            {
                network: "telegram",
                url: `https://t.me/share/url?url=${url}&text=${message}`,
            },
            {
                network: "invite",
                url: "",
            },
        ],
        [message, hashtag, tweet],
    ) as { network: sway.TSharePlatform & "invite"; url: string }[];

    return (
        <Modal centered show={isOpen} aria-labelledby="share-buttons-dialog" onHide={handleClose}>
            <Modal.Header>
                <Modal.Title id="share-buttons-dialog">
                    {user_vote
                        ? "Earn Sway by sharing the votes you make or by inviting friends."
                        : "Share this legislation with people you know."}
                </Modal.Title>
            </Modal.Header>
            <Modal.Body className="pointer">
                {user_vote && (
                    <>
                        <div className="row align-items-center">
                            {items.map((i) =>
                                i.network === "invite" ? (
                                    <div key={i.network} className="col-4 text-center my-3">
                                        <InviteDialogShareButton
                                            className="rounded-circle border border-primary border-1"
                                            iconStyle={{ verticalAlign: "top", fontSize: "20px" }}
                                            buttonStyle={{ width: "50px", height: "50px" }}
                                        />
                                    </div>
                                ) : (
                                    <ButtonUnstyled
                                        key={i.url}
                                        className="col-4 text-center my-3"
                                        onClick={() => open(i.url)}
                                    >
                                        <SocialIcon url={i.url} onClick={() => open(i.url)} target="_blank" />
                                    </ButtonUnstyled>
                                ),
                            )}
                        </div>
                        <hr />
                    </>
                )}
                <div className="row my-3">
                    <div className="col">
                        {user_vote && <p className="mb-2">Share this legislation with people you know.</p>}

                        <p>Click/tap to copy:</p>
                        <Button variant="link" className="p-0 ellipses mt-2" onClick={handleCopy}>
                            <FiCopy title="Copy" onClick={handleCopy} />
                            &nbsp;{window.location.href}
                        </Button>
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
