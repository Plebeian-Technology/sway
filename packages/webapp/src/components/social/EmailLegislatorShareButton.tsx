import { sway } from "sway";
import { SWAY_COLORS } from "../../utils";
import ContactLegislatorDialogButton from "../dialogs/ContactLegislatorDialogButton";

interface IProps {
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

const EmailLegislatorShareButton: React.FC<IProps> = ({ userVote, iconStyle, className }) => {
    return (
        <div className={`pointer ${className || ""}`} style={{ ...style, ...iconStyle }}>
            <ContactLegislatorDialogButton type={"email"} userVote={userVote} />
        </div>
    );
};

export default EmailLegislatorShareButton;
