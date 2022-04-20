import { useState } from "react";
import { Dropdown } from "react-bootstrap";
import { FaUserPlus } from "react-icons/fa";
import { sway } from "sway";
import InviteDialog from "./InviteDialog";

const InviteIconDialog = ({
    user,
    withText,
}: {
    user: sway.IUser;
    withText?: boolean;
    iconStyle?: React.CSSProperties;
}) => {
    const [open, setOpen] = useState<boolean>(false);

    return (
        <Dropdown.Item
            onClick={() => setOpen(!open)}
            className="row mx-0 fs-5 py-3 align-items-center"
        >
            <span className="col-1 px-0 text-start opacity-75">
                <FaUserPlus />
            </span>
            <span className="col-10">{withText && <span>Invite Friends</span>}</span>
            <span className="col-1">
                <InviteDialog open={open} user={user} handleClose={() => setOpen(false)} />
            </span>
        </Dropdown.Item>
    );
};

export default InviteIconDialog;
