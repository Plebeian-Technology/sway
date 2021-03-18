import { createStyles, makeStyles } from "@material-ui/core";
import { sway } from "sway";
import { SWAY_COLORS } from "../../utils";
import InviteIconDialog from "../dialogs/InviteIconDialog";

const useStyles = makeStyles(() =>
    createStyles({
        button: {
            width: 64,
            height: 64,
            borderRadius: 0,
            marginBottom: 3,
            backgroundColor: SWAY_COLORS.primary,
            color: SWAY_COLORS.secondary,
            cursor: "pointer",
        },
    }),
);

const InviteDialogShareButton: React.FC<{ user: sway.IUser, iconStyle?: sway.IPlainObject }> = ({ user, iconStyle }) => {
    const classes = useStyles();

    return (
        <div id={"invite-container-share-button"} className={classes.button}>
            <InviteIconDialog user={user} iconStyle={iconStyle} />
        </div>
    );
};

export default InviteDialogShareButton;
