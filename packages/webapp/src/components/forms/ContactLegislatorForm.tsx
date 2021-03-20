/** @format */

import { EXECUTIVE_BRANCH_TITLES, Support } from "@sway/constants";
import {
    formatPhone,
    isAtLargeLegislator,
    IS_DEVELOPMENT,
    titleize,
} from "@sway/utils";
import copy from "copy-to-clipboard";
import React from "react";
import { sway } from "sway";
import { notify } from "../../utils";
import EmailLegislatorForm from "./EmailLegislatorForm";
import PhoneLegislatorForm from "./PhoneLegislatorForm";

interface IProps {
    user: sway.IUser;
    legislator: sway.ILegislator;
    handleSubmit: ({ message }: { message: string }) => void;
    handleClose: (close: boolean | React.MouseEvent<HTMLElement>) => void;
    type: "email" | "phone";
    userVote?: sway.IUserVote;
}

const ContactLegislatorForm: React.FC<IProps> = ({
    user,
    legislator,
    type,
    userVote,
    ...props
}) => {
    const methods = {
        address: function (): string {
            const address2 = user.address2;
            if (address2) {
                return `${user.address1}, ${address2} ${user.city}, ${user.region} ${user.postalCode}-${user.postalCodeExtension}`;
            }
            return `${user.address1}, ${user.city}, ${user.region} ${user.postalCode}-${user.postalCodeExtension}`;
        },

        registeredVoter: function (): string {
            if (!user.isRegisteredToVote) {
                return "I";
            }
            return "I am registered to vote and";
        },

        shortSupport: function (): string {
            if (!userVote) return "";

            if (userVote.support === Support.For) {
                return "support";
            }
            return "oppose";
        },

        longSupport: function (): string {
            if (!userVote) return "";

            if (
                EXECUTIVE_BRANCH_TITLES.includes(legislator.title.toLowerCase())
            ) {
                return this.shortSupport();
            }
            if (userVote.support === Support.For) {
                return "vote in support of";
            }
            return `vote ${Support.Against}`;
        },

        residence: function (): string {
            if (isAtLargeLegislator(legislator)) {
                return `in ${titleize(user.city)}`;
            }
            return `in your district`;
        },

        getLegislatorTitle: function () {
            if (legislator.title?.toLowerCase() === "councilmember") {
                return "Council Member";
            }
            return legislator.title;
        },

        defaultMessage: function (): string {
            if (!userVote) return "";
            return `Hello ${this.getLegislatorTitle()} ${
                legislator.last_name
            }, my name is ${
                user.name
            } and ${this.registeredVoter()} reside ${this.residence()} at ${titleize(
                this.address(),
            )}.\n\r\n\rPlease ${this.longSupport()} bill ${
                userVote.billFirestoreId
            }.\n\r\n\rThank you, ${user.name}`;
        },

        legislatorEmail: function (): string {
            if (IS_DEVELOPMENT) {
                return "legis@sway.vote";
            }
            return legislator.email;
        },

        legislatorEmailPreview: function (): string {
            if (IS_DEVELOPMENT) {
                return `(dev) legis@sway.vote - (prod) ${legislator.email}`;
            }
            return legislator.email;
        },

        legislatorPhone: function (): string {
            if (IS_DEVELOPMENT) {
                return formatPhone("1234567890");
            }
            return formatPhone(legislator.phone);
        },

        legislatorPhonePreview: function (): string {
            if (IS_DEVELOPMENT) {
                return `(dev) ${formatPhone(
                    "1234567890",
                )} - (prod) ${formatPhone(legislator.phone)}`;
            }
            return formatPhone(legislator.phone);
        },

        handleCopy: function (): string {
            copy(
                type === "phone"
                    ? this.legislatorPhone()
                    : this.legislatorEmail(),
                {
                    message: "Click to Copy",
                    format: "text/plain",
                    onCopy: () =>
                        notify({
                            level: "info",
                            message: `Copied ${type} to clipboard.`,
                        }),
                },
            );
            return "";
        },
    };

    return type === "phone" ? (
        <PhoneLegislatorForm
            {...props}
            legislator={legislator}
            methods={methods}
        />
    ) : (
        <EmailLegislatorForm
            {...props}
            user={user}
            legislator={legislator}
            userVote={userVote}
            methods={methods}
        />
    );
};

export default ContactLegislatorForm;
