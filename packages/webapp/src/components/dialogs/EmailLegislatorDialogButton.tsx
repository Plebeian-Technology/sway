import { Send } from "@material-ui/icons";
import { findLocale, userLocaleFromLocales } from "@sway/utils";
import { useEffect, useState } from "react";
import { sway } from "sway";
import { useHookedRepresentatives } from "../../hooks/legislators";
import CenteredDivCol from "../shared/CenteredDivCol";
import EmailLegislatorDialog from "./EmailLegislatorDialog";

interface IProps {
    user: sway.IUser;
    userLocale: sway.IUserLocale;
    userVote: sway.IUserVote;
}

const EmailLegislatorDialogButton: React.FC<IProps> = ({
    user,
    userLocale,
    userVote,
}) => {
    const [open, setOpen] = useState<boolean>(false);
    const [representatives, getRepresentatives] = useHookedRepresentatives();
    useEffect(() => {
        getRepresentatives(user, userLocale, true);
    }, [getRepresentatives]);

    if (!representatives) {
        return (
            <CenteredDivCol
                style={{ width: "100%", height: "100%", zIndex: 10000 }}
            >
                <Send onClick={() => setOpen(false)} />
            </CenteredDivCol>
        );
    }

    const legislators = representatives?.representatives.map(
        (r) => r.legislator,
    );
    const children = (
        <>
            <Send onClick={() => setOpen(!open)} />
            <EmailLegislatorDialog
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

export default EmailLegislatorDialogButton;
