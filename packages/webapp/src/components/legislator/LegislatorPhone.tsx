import { Phone } from "@material-ui/icons";
import { formatPhone } from "@sway/utils";
import { useState } from "react";
import { sway } from "sway";
import { SWAY_COLORS } from "../../utils";
import PhoneLegislatorDialog from "../dialogs/PhoneLegislatorDialog";
import LegislatorCardSocialItem from "./LegislatorCardSocialItem";

interface IProps {
    user: sway.IUser;
    locale: sway.ILocale;
    legislator: sway.ILegislator;
    handleCopy: (email: string) => void;
}

const Button = ({ handleOpen }: { handleOpen: () => void }) => {
    return <Phone style={{ color: SWAY_COLORS.white }} onClick={handleOpen} />;
};

const LegislatorPhone: React.FC<IProps> = ({
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
                title={"Phone"}
                text={formatPhone(legislator.phone)}
                handleCopy={handleCopy}
                Icon={() => <Button handleOpen={handleOpen} />}
            />

            <PhoneLegislatorDialog
                user={user}
                locale={locale}
                legislators={[legislator]}
                open={open}
                handleClose={handleClose}
            />
        </>
    );
};

export default LegislatorPhone;
