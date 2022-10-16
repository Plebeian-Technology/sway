import { userLocaleFromLocales } from "@sway/utils";
import { sway } from "sway";
import { SWAY_COLORS } from "../../utils";
import ContactLegislatorDialogButton from "../dialogs/ContactLegislatorDialogButton";

interface IProps {
    user: sway.IUser;
    locale: sway.ILocale;
    userVote: sway.IUserVote;
    iconStyle?: React.CSSProperties;
    className?: string;
}

const style = {
    width: 64,
    height: 64,
    borderRadius: 0,
    marginBottom: 3,
    backgroundColor: SWAY_COLORS.primaryLight,
    color: SWAY_COLORS.secondary,
};

const EmailLegislatorShareButton: React.FC<IProps> = ({
    user,
    locale,
    userVote,
    iconStyle,
    className,
}) => {
    const userLocale = userLocaleFromLocales(user, locale);
    if (!userLocale) {
        return null;
    }

    return (
        <div className={`pointer ${className || ""}`} style={{ ...style, ...iconStyle }}>
            <ContactLegislatorDialogButton
                type={"email"}
                user={user}
                userLocale={userLocale}
                userVote={userVote}
            />
        </div>
    );
};

export default EmailLegislatorShareButton;
