/** @format */

import { sway } from "sway";
import EmailLegislatorForm from "./EmailLegislatorForm";
import PhoneLegislatorForm from "./PhoneLegislatorForm";

interface IProps {
    user: sway.IUser;
    legislator: sway.ILegislator;
    type: "email" | "phone";
    userVote?: sway.IUserVote;
    legislators: sway.ILegislator[];
    selectedLegislator: sway.ILegislator;
    handleChangeLegislator: (event: React.ChangeEvent<{ value: unknown }>) => void;
    methods: {
        [key: string]: () => string;
    };
}

const ContactLegislatorForm: React.FC<IProps> = ({
    user,
    legislator,
    type,
    userVote,
    ...props
}) => {
    return type === "phone" ? (
        <PhoneLegislatorForm {...props} type={type} legislator={legislator} />
    ) : (
        <EmailLegislatorForm
            {...props}
            type={type}
            user={user}
            legislator={legislator}
            userVote={userVote}
        />
    );
};

export default ContactLegislatorForm;
