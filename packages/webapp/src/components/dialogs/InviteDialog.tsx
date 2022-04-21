/** @format */
import { ContentCopy } from "@mui/icons-material";
import { Tooltip } from "@mui/material";
import Button from "@mui/material/Button";
import copy from "copy-to-clipboard";
import { useState } from "react";
import { Modal } from "react-bootstrap";
import { sway } from "sway";
import { notify } from "../../utils";
import InviteForm from "../forms/InviteForm";
import CenteredLoading from "./CenteredLoading";

interface IProps {
    user: sway.IUser;
    open: boolean;
    handleClose: (close: boolean | React.MouseEvent<HTMLElement>) => void;
}

const InviteDialog: React.FC<IProps> = ({ user, open, handleClose }) => {
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
            open={open}
            onClose={() => handleClose(false)}
            aria-labelledby="alert-dialog-title"
            aria-describedby="alert-dialog-description"
        >
            <Modal.Header>
                <Modal.Title id="alert-dialog-title">
                    Invite friends through email or a link.
                </Modal.Title>
            </Modal.Header>
            <Modal.Body className="pointer">
                <p className="mb-2">The more friends you invite, the greater your sway.</p>
                {isSendingInvites && <CenteredLoading style={{ margin: "5px auto" }} />}

                <InviteForm user={user} setIsSendingInvites={setIsSendingInvites} />

                <p className="mt-2" onClick={() => handleCopy(link)}>
                    {"Or invite your friends using this link:"}
                </p>
                <p className="ellipses mt-2" onClick={() => handleCopy(link)}>
                    {link}
                </p>
                <Tooltip title="Copy Link" placement="right" onClick={() => handleCopy(link)}>
                    <div className={"pointer text-center"} onClick={() => handleCopy(link)}>
                        <ContentCopy />
                    </div>
                </Tooltip>
            </Modal.Body>
            <Modal.Footer>
                <Button onClick={handleClose} color="primary">
                    Close
                </Button>
            </Modal.Footer>
        </Modal>
    );
};

export default InviteDialog;
