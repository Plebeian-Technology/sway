/** @format */

import copy from "copy-to-clipboard";
import { useCallback, useState } from "react";
import { Button, Modal } from "react-bootstrap";
import { FiCopy } from "react-icons/fi";
import { useUser } from "../../hooks/users/useUser";
import { notify } from "../../sway_utils";
import InviteForm from "../forms/InviteForm";

interface IProps {
    open: boolean;
    handleClose: (e?: React.MouseEvent<HTMLButtonElement>) => void;
}

const InviteDialog: React.FC<IProps> = ({ open, handleClose }) => {
    const user = useUser();
    const [isSendingInvites, setSendingInvites] = useState<boolean>(false);

    const link = `https://${process.env.REACT_APP_ORIGIN}/invite/${user.uid}`;

    const handleCopy = useCallback(() => {
        copy(link, {
            message: "Click to Copy",
            format: "text/plain",
            onCopy: () =>
                notify({
                    level: "info",
                    title: "Copied link to clipboard.",
                }),
        });
    }, [link]);

    return (
        <Modal
            centered
            show={open}
            onHide={handleClose}
            aria-labelledby="alert-dialog-title"
            aria-describedby="alert-dialog-description"
            size="xl"
        >
            <Modal.Header>
                <Modal.Title id="alert-dialog-title">
                    Invite friends using email or a link.
                </Modal.Title>
            </Modal.Header>
            <Modal.Body className="pointer">
                <p className="mb-2">The more friends you invite, the greater your sway.</p>

                <InviteForm
                    isSendingInvites={isSendingInvites}
                    setSendingInvites={setSendingInvites}
                />

                <p className="mt-2" onClick={handleCopy}>
                    {"Or invite your friends using this link:"}
                </p>
                <p className="ellipses mt-2" onClick={handleCopy}>
                    <FiCopy onClick={handleCopy} />
                    &nbsp;{link}
                </p>
            </Modal.Body>
            <Modal.Footer>
                <Button variant="secondary" onClick={handleClose} disabled={isSendingInvites}>
                    Close
                </Button>
            </Modal.Footer>
        </Modal>
    );
};

export default InviteDialog;
