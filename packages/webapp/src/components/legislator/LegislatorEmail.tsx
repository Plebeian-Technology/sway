import { EmailOutlined } from "@material-ui/icons";
import { useState } from "react";
import { sway } from "sway";
import { SWAY_COLORS } from "../../utils";
import EmailLegislatorDialog from "../dialogs/EmailLegislatorDialog";
import LegislatorCardSocialItem from "./LegislatorCardSocialItem";

interface IProps {
    user: sway.IUser;
    locale: sway.ILocale;
    legislator: sway.ILegislator;
    handleCopy: (email: string) => void;
}

const Button = ({ handleOpen }: { handleOpen: () => void }) => {
    return <EmailOutlined style={{ color: SWAY_COLORS.white }} onClick={handleOpen} />;
};

const LegislatorEmail: React.FC<IProps> = ({
    user,
    locale,
    legislator,
    handleCopy,
}) => {
    const [open, setOpen] = useState<boolean>(false);

    const { email } = legislator;
    if (!email) return null;

    const handleOpen = () => setOpen(true);
    const handleClose = () => setOpen(false);

    return (
        <>
            <LegislatorCardSocialItem
                title={"Email"}
                text={email}
                handleCopy={handleCopy}
                Icon={() => <Button handleOpen={handleOpen} />}
            />
            <EmailLegislatorDialog
                user={user}
                locale={locale}
                legislators={[legislator]}
                open={open}
                handleClose={handleClose}
            />
        </>
    );
};

export default LegislatorEmail;
