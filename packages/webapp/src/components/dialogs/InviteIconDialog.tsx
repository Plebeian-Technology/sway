import { GroupAdd } from "@material-ui/icons";
import { useState } from "react";
import { sway } from "sway";
import CenteredDivCol from "../shared/CenteredDivCol";
import InviteDialog from "./InviteDialog";

const InviteIconDialog = ({ user }: { user: sway.IUser }) => {
    const [open, setOpen] = useState<boolean>(false);

    const children = (
        <>
            <GroupAdd onClick={() => setOpen(!open)} />
            <InviteDialog
                open={open}
                user={user}
                handleClose={() => setOpen(false)}
            />
        </>
    );

    if (open) {
        return (
            <CenteredDivCol
                style={{ height: "100%", zIndex: 10000 }}
            >
                {children}
            </CenteredDivCol>
        );
    }
    return (
        <CenteredDivCol
            style={{ height: "100%", zIndex: 10000 }}
            onClick={() => setOpen(true)}
        >
            {children}
        </CenteredDivCol>
    );
};

export default InviteIconDialog;
