import { Mail } from "@mui/icons-material";
import { useEffect, useState } from "react";
import { sway } from "sway";
import { useHookedRepresentatives } from "../../hooks/legislators";
import { handleError } from "../../utils";
import CenteredDivCol from "../shared/CenteredDivCol";
import ContactLegislatorDialog from "./ContactLegislatorDialog";

interface IProps {
    type: "phone" | "email";
    user: sway.IUser;
    userLocale: sway.IUserLocale;
    userVote: sway.IUserVote;
}

const ContactLegislatorDialogButton: React.FC<IProps> = ({
    type,
    user,
    userLocale,
    userVote,
}) => {
    const [open, setOpen] = useState<boolean>(false);
    const [representatives, getRepresentatives] = useHookedRepresentatives();
    useEffect(() => {
        getRepresentatives(user, userLocale, true).catch(handleError);
    }, [getRepresentatives]);

    if (!representatives) {
        return (
            <CenteredDivCol
                style={{ width: "100%", height: "100%", zIndex: 10000 }}
            >
                <Mail onClick={() => setOpen(false)} />
            </CenteredDivCol>
        );
    }

    const legislators = representatives?.representatives;
    const children = (
        <>
            <Mail
                id={`${type}-legislator-share-button`}
                onClick={() => setOpen(!open)}
            />
            <ContactLegislatorDialog
                type={type}
                user={user}
                locale={userLocale}
                userVote={userVote}
                legislators={legislators}
                open={open}
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

export default ContactLegislatorDialogButton;