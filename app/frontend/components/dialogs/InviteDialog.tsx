/** @format */

import InviteBody from "app/frontend/components/dialogs/invites/InviteBody";
import { Button, Modal } from "react-bootstrap";
import { useUser } from "../../hooks/users/useUser";

interface IProps {
    open: boolean;
    handleClose: (e?: React.MouseEvent<HTMLButtonElement>) => void;
}

const InviteDialog: React.FC<IProps> = ({ open, handleClose }) => {
    const user = useUser();

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
                <Modal.Title id="alert-dialog-title">Invite friends using email or a link.</Modal.Title>
            </Modal.Header>

            <Modal.Body className="pointer">
                <InviteBody />
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
