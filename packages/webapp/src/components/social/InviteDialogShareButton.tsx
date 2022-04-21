import { useState } from "react";
import { Button } from "react-bootstrap";
import { FaUserPlus } from "react-icons/fa";
import { sway } from "sway";
import InviteDialog from "../dialogs/InviteDialog";

const InviteDialogShareButton: React.FC<{
    user: sway.IUser;
    iconStyle?: React.CSSProperties;
}> = ({ user, iconStyle }) => {
    const [open, setOpen] = useState<boolean>(false);

    const handleOpen = () => setOpen(!open);

    return (
        <Button
            onClick={handleOpen}
            className={"pointer border border-2 rounded text-center"}
            style={{ width: 64, height: 64, ...iconStyle }}
        >
            <FaUserPlus />
            <InviteDialog open={open} user={user} handleClose={handleOpen} />
        </Button>
    );
};

export default InviteDialogShareButton;
