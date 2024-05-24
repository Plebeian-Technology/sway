/** @format */

import ContactLegislatorFormEditable from "app/frontend/components/forms/ContactLegislatorFormEditable";
import { sway } from "sway";

interface IProps {
    user: sway.IUser;
    legislator: sway.ILegislator;
    userVote?: sway.IUserVote;
    type: "email" | "phone";
    methods: {
        [key: string]: () => string;
    };
}

const EmailLegislatorForm: React.FC<IProps> = (
    props
) => {

    return (
        <>
            <span>Don't know what to say? Here's an editable prompt for you.</span>
            <ContactLegislatorFormEditable {...props} />
        </>
    );
};

export default EmailLegislatorForm;
