import { logDev } from "@sway/utils";
import { Button, Modal } from "react-bootstrap";

import { sway } from "sway";
import { GAINED_SWAY_MESSAGE, handleError, notify, swayFireClient, withTadas } from "../../utils";
import EmailLegislatorShareButton from "./EmailLegislatorShareButton";
import InviteDialogShareButton from "./InviteDialogShareButton";

import { RWebShare } from "react-web-share";

interface IProps {
    bill: sway.IBill;
    locale: sway.ILocale;
    user: sway.IUser;
    userVote?: sway.IUserVote;
    handleClose: () => void;
    isOpen: boolean;
}

enum ESocial {
    Email = "email",
    Twitter = "twitter",
    Facebook = "facebook",
    WhatsApp = "whatsapp",
    Telegram = "telegram",
}

const ShareDialog: React.FC<IProps> = ({ bill, locale, user, userVote, handleClose, isOpen }) => {
    const message = "I voted on the Sway bill of the week. Will you sway with me?";
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
        <Modal centered show={isOpen} aria-labelledby="share-buttons-dialog">
            <Modal.Header>
                <Modal.Title id="share-buttons-dialog">
                    Earn Sway by sharing the votes you make or by inviting friends.
                </Modal.Title>
            </Modal.Header>
            <Modal.Body className="pointer">
                <div className="row justify-content-center">
                    <div>
                        <RWebShare
                            data={{
                                title: message,
                                url,
                            }}
                            sites={[
                                "facebook",
                                "twitter",
                                "whatsapp",
                                "reddit",
                                "telegram",
                                "copy",
                            ]}
                            onClick={() => console.log("shared successfully!")}
                        >
                            <button>Share 🔗</button>
                        </RWebShare>
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
            </Modal.Body>
            <Modal.Footer>
                <Button onClick={handleClose}>Close</Button>
            </Modal.Footer>
        </Modal>
    );
};

export default ShareDialog;
