import { GroupAdd } from "@mui/icons-material";
import { ListItem, ListItemIcon, ListItemText } from "@mui/material";
import { useState } from "react";
import { sway } from "sway";
import InviteDialog from "./InviteDialog";

const InviteIconDialog = ({
    user,
    withText,
}: {
    user: sway.IUser;
    withText?: boolean;
    iconStyle?: sway.IPlainObject;
}) => {
    const [open, setOpen] = useState<boolean>(false);

    return (
        <ListItem button className="row px-0" onClick={() => setOpen(!open)}>
            <ListItemIcon className="col-2 pe-0" style={{ minWidth: 0 }}>
                <GroupAdd />
            </ListItemIcon>
            {withText && (
                <ListItemText className="col-9 px-0">
                    Invite Friends
                </ListItemText>
            )}
            <InviteDialog
                open={open}
                user={user}
                handleClose={() => setOpen(false)}
            />
        </ListItem>
    );
};

export default InviteIconDialog;