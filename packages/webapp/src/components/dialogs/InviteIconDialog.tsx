import { useCallback, useState } from "react";
import { Dropdown } from "react-bootstrap";
import { FiUserPlus } from "react-icons/fi";
import InviteDialog from "./InviteDialog";

const InviteIconDialog = ({
    withText,
}: {
    withText?: boolean;
    iconStyle?: React.CSSProperties;
}) => {
    const [open, setOpen] = useState<boolean>(false);
    const handleOpenModal = useCallback(() => setOpen(true), []);
    const handleClose = useCallback(() => setOpen(false), []);

    return (
        <Dropdown.Item onClick={handleOpenModal} className="row mx-0 fs-5 py-3 align-items-center">
            <span className="col-1 px-0 text-start opacity-75">
                <FiUserPlus />
            </span>
            <span className="col-10">{withText && <span>Invite Friends</span>}</span>
            <span className="col-1">
                <InviteDialog open={open} handleClose={handleClose} />
            </span>
        </Dropdown.Item>
    );
};

export default InviteIconDialog;
