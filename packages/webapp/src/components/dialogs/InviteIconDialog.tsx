import { ListItemIcon, Typography } from "@material-ui/core";
import { GroupAdd } from "@material-ui/icons";
import { useState } from "react";
import { sway } from "sway";
import { SWAY_COLORS } from "../../utils";
import CenteredDivCol from "../shared/CenteredDivCol";
import CenteredDivRow from "../shared/CenteredDivRow";
import InviteDialog from "./InviteDialog";

const InviteIconDialog = ({ user, withText, iconStyle }: { user: sway.IUser, withText?: boolean, iconStyle?: sway.IPlainObject }) => {
    const [open, setOpen] = useState<boolean>(false);

    const _iconStyle = iconStyle ? iconStyle : {}

    const children = (
        <>
            <CenteredDivRow
                style={{ width: "100%", justifyContent: "flex-start" }}
            >
                <ListItemIcon style={{ justifyContent: !withText ? "center" : undefined }}>
                    <GroupAdd onClick={() => setOpen(!open)} style={_iconStyle} />
                </ListItemIcon>
                {withText && <Typography style={{ color: SWAY_COLORS.black }}>
                    Invite Friends
                </Typography>}
            </CenteredDivRow>
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
                style={{ width: "100%", height: "100%", zIndex: 10000 }}
            >
                {children}
            </CenteredDivCol>
        );
    }
    return (
        <CenteredDivCol
            style={{ width: "100%", height: "100%", zIndex: 10000 }}
            onClick={() => setOpen(true)}
        >
            {children}
        </CenteredDivCol>
    );
};

export default InviteIconDialog;

// Damion.Cooper@projectpneuma.org

// kategmac@icloud.com
// lena@lenaevergreen.co
// kelvinj1@umbc.edu
// eric@baltimoreunited.org
// kevon@blocbyblocknews.com
// trish@oforiandco.com
// dave@legisme.org
// dmstheman@hotmail.com
// ssprigg@camdenpartners.com
