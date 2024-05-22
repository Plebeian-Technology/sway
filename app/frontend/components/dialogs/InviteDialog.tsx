/** @format */

import copy from "copy-to-clipboard";
import { useCallback, useMemo } from "react";
import { Button, Modal } from "react-bootstrap";
import { FiCopy } from "react-icons/fi";
import { useUser } from "../../hooks/users/useUser";
import { notify } from "../../sway_utils";

interface IProps {
    open: boolean;
    handleClose: (e?: React.MouseEvent<HTMLButtonElement>) => void;
}

const InviteDialog: React.FC<IProps> = ({ open, handleClose }) => {
    const user = useUser();
    const link = useMemo(() => `${window.location.origin}${user.inviteUrl}`, [user.inviteUrl])

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

    if (!user.inviteUrl) {
        return null;
    }

    return (
        <Modal
            centered
            show={open}
            onHide={handleClose}
            aria-labelledby="alert-dialog-title"
            aria-describedby="alert-dialog-description"
            size="lg"
        >
            <Modal.Header>
                <Modal.Title id="alert-dialog-title">
                    Invite friends using email or a link.
                </Modal.Title>
            </Modal.Header>

            <Modal.Body className="pointer">
                <p className="mb-2">The more friends you invite, the greater your sway.</p>

                <p className="mt-2">
                    Invite your friends using this link:
                </p>
                <Button variant="link" className="ellipses mt-2" onClick={handleCopy}>
                    <FiCopy onClick={handleCopy} />
                    &nbsp;{link}
                </Button>
            </Modal.Body>
            <Modal.Footer>
                <Button variant="secondary" onClick={handleClose}>
                    Close
                </Button>
            </Modal.Footer>
        </Modal>
    );
};

export default InviteDialog;
