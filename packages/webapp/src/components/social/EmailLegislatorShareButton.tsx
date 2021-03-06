import { createStyles, makeStyles } from "@material-ui/core";
import { userLocaleFromLocales } from "@sway/utils";
import { sway } from "sway";
import { SWAY_COLORS } from "../../utils";
import EmailLegislatorDialogButton from "../dialogs/EmailLegislatorDialogButton";

interface IProps {
    user: sway.IUser;
    locale: sway.ILocale;
    userVote: sway.IUserVote;
}

const useStyles = makeStyles(() =>
    createStyles({
        button: {
            width: 64,
            height: 64,
            borderRadius: 0,
            marginBottom: 3,
            backgroundColor: SWAY_COLORS.primaryLight,
            color: SWAY_COLORS.secondary,
            cursor: "pointer",
        },
    }),
);

const EmailLegislatorShareButton: React.FC<IProps> = ({
    user,
    locale,
    userVote,
}) => {
    const classes = useStyles();
    const userLocale = userLocaleFromLocales(user, locale);
    if (!userLocale) {
        return null;
    }

    return (
        <div className={classes.button}>
            <EmailLegislatorDialogButton
                user={user}
                userLocale={userLocale}
                userVote={userVote}
            />
        </div>
    );
};

export default EmailLegislatorShareButton;
