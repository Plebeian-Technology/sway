import { GroupAdd } from "@material-ui/icons";
import { useState } from "react";
import { sway } from "sway";
import InviteDialog from "./InviteDialog";

const InviteIconDialog = ({ user }: { user: sway.IUser }) => {
    const [open, setOpen] = useState<boolean>(false);

    return (
        <>
            <GroupAdd onClick={() => setOpen(!open)} />
            <InviteDialog
                open={open}
                user={user}
                handleClose={() => setOpen(false)}
            />
        </>
    );
};

export default InviteIconDialog;
