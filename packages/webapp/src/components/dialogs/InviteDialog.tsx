/** @format */

import copy from "copy-to-clipboard";
import { useState } from "react";
import { Button, Modal } from "react-bootstrap";
import { FiCopy } from "react-icons/fi";
import { useUser } from "../../hooks";
import { notify } from "../../utils";
import InviteForm from "../forms/InviteForm";
import SwaySpinner from "../SwaySpinner";

interface IProps {
    open: boolean;
    handleClose: () => void;
}

const InviteDialog: React.FC<IProps> = ({ open, handleClose }) => {
    const user = useUser();
    const [isSendingInvites, setIsSendingInvites] = useState<boolean>(false);

    const link = `https://${process.env.REACT_APP_ORIGIN}/invite/${user.uid}`;

    const handleCopy = (value: string) => {
        copy(value, {
            message: "Click to Copy",
            format: "text/plain",
            onCopy: () =>
                notify({
                    level: "info",
                    title: "Copied link to clipboard.",
                }),
        });
    };

    return (
        <Modal
            centered
            show={open}
            onHide={handleClose}
            aria-labelledby="alert-dialog-title"
            aria-describedby="alert-dialog-description"
        >
            <Modal.Header>
                <Modal.Title id="alert-dialog-title">
                    Invite friends using email or a link.
                </Modal.Title>
            </Modal.Header>
            <Modal.Body className="pointer">
                <p className="mb-2">The more friends you invite, the greater your sway.</p>

                <InviteForm user={user} setIsSendingInvites={setIsSendingInvites} />

                <p className="mt-2" onClick={() => handleCopy(link)}>
                    {"Or invite your friends using this link:"}
                </p>
                <p className="ellipses mt-2" onClick={() => handleCopy(link)}>
                    <FiCopy onClick={() => handleCopy(link)} />
                    &nbsp;{link}
                </p>
            </Modal.Body>
            <Modal.Footer>
                <SwaySpinner isHidden={!isSendingInvites} />
                <Button variant="secondary" onClick={handleClose}>
                    Close
                </Button>
            </Modal.Footer>
        </Modal>
    );
};

export default InviteDialog;
