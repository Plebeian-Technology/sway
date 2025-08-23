/** @format */

import { sway } from "sway";
import EmailLegislatorForm from "./EmailLegislatorForm";
import PhoneLegislatorForm from "./PhoneLegislatorForm";

interface IProps {
    user: sway.IUser;
    type: "email" | "phone";
    user_vote?: sway.IUserVote;
    legislator: sway.ILegislator;
    methods: {
        [key: string]: () => string;
    };
}

const ContactLegislatorForm: React.FC<IProps> = ({ user, legislator, type, user_vote, ...props }) => {
    return type === "phone" ? (
        <PhoneLegislatorForm {...props} type={type} legislator={legislator} user={user} user_vote={user_vote} />
    ) : (
        <EmailLegislatorForm {...props} type={type} legislator={legislator} user={user} user_vote={user_vote} />
    );
};

export default ContactLegislatorForm;
