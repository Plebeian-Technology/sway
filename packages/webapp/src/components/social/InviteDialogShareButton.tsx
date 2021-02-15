import { Button, createStyles, makeStyles } from "@material-ui/core";
import { sway } from "sway";
import { SWAY_COLORS } from "../../utils";
import InviteIconDialog from "../dialogs/InviteIconDialog";

const useStyles = makeStyles(() =>
    createStyles({
        button: {
            width: 64,
            height: 64,
            borderRadius: 0,
            marginBottom: 4,
            backgroundColor: SWAY_COLORS.primary,
            color: SWAY_COLORS.secondary,
        },
    }),
);

const InviteDialogShareButton: React.FC<{ user: sway.IUser }> = ({ user }) => {
    const classes = useStyles();

    return (
        <Button className={classes.button} variant="contained" style={{ boxShadow: "none" }}>
            <InviteIconDialog user={user} />
        </Button>
    );
};

export default InviteDialogShareButton;
