/** @format */

import { sway } from "sway";
import EmailLegislatorForm from "./EmailLegislatorForm";
import PhoneLegislatorForm from "./PhoneLegislatorForm";

interface IProps {
    user: sway.IUser;
    type: "email" | "phone";
    userVote?: sway.IUserVote;
    legislator: sway.ILegislator;
    methods: {
        [key: string]: () => string;
    };
}

const ContactLegislatorForm: React.FC<IProps> = ({ user, legislator, type, userVote, ...props }) => {
    return type === "phone" ? (
        <PhoneLegislatorForm {...props} type={type} legislator={legislator} user={user} userVote={userVote} />
    ) : (
        <EmailLegislatorForm {...props} type={type} legislator={legislator} user={user} userVote={userVote} />
    );
};

export default ContactLegislatorForm;
