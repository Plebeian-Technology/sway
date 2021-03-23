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
    const address = (): string => {
        const address2 = user.address2;
        if (address2) {
            return `${user.address1}, ${address2} ${user.city}, ${user.region} ${user.postalCode}-${user.postalCodeExtension}`;
        }
        return `${user.address1}, ${user.city}, ${user.region} ${user.postalCode}-${user.postalCodeExtension}`;
    };

    const registeredVoter = (): string => {
        if (!user.isRegisteredToVote) {
            return "I";
        }
        return "I am registered to vote and";
    };

    const shortSupport = (): string => {
        if (!userVote) return "";

        if (userVote.support === Support.For) {
            return "support";
        }
        return "oppose";
    };

    const longSupport = (): string => {
        if (!userVote) return "";

        if (EXECUTIVE_BRANCH_TITLES.includes(legislator.title.toLowerCase())) {
            return shortSupport();
        }
        if (userVote.support === Support.For) {
            return "vote in support of";
        }
        return `vote ${Support.Against}`;
    };

    const residence = (): string => {
        if (isAtLargeLegislator(legislator)) {
            return `in ${titleize(user.city)}`;
        }
        return `in your district`;
    };

    const getLegislatorTitle = (): string => {
        if (legislator.title?.toLowerCase() === "councilmember") {
            return "Council Member";
        }
        return legislator.title;
    };

    const defaultMessage = (): string => {
        const userVoteText = userVote
            ? `Please ${longSupport()} bill ${
                  userVote.billFirestoreId
              }.\n\r\n\r`
            : `I am ${
                  type === "phone" ? "calling" : "writing"
              } to you today because I would like you to support...\n\r\n\r`;
        return `Hello ${getLegislatorTitle()} ${
            legislator.last_name
        }, my name is ${
            user.name
        } and ${registeredVoter()} reside ${residence()} at ${titleize(
            address(),
        )}.\n\r\n\r${userVoteText}Thank you, ${user.name}`;
    };

    const getLegislatorEmail = (): string => {
        if (IS_DEVELOPMENT) {
            return "legis@sway.vote";
        }
        return legislator.email;
    };

    const getLegislatorEmailPreview = (): string => {
        if (IS_DEVELOPMENT) {
            return `(dev) legis@sway.vote - (prod) ${legislator.email}`;
        }
        return legislator.email;
    };

    const getLegislatorPhone = (): string => {
        if (IS_DEVELOPMENT) {
            return formatPhone("1234567890");
        }
        return formatPhone(legislator.phone);
    };

    const getLegislatorPhonePreview = (): string => {
        if (IS_DEVELOPMENT) {
            return `(dev) ${formatPhone("1234567890")} - (prod) ${formatPhone(
                legislator.phone,
            )}`;
        }
        return formatPhone(legislator.phone);
    };

    const handleCopy = (): string => {
        const toCopy =
            type === "phone" ? getLegislatorPhone() : getLegislatorEmail();
        copy(toCopy, {
            message: "Click to Copy",
            format: "text/plain",
            onCopy: () =>
                notify({
                    level: "info",
                    title: `Copied ${type} to clipboard.`,
                }),
        });
        return "";
    };

    const methods = {
        address,
        registeredVoter,
        shortSupport,
        longSupport,
        residence,
        defaultMessage,
        getLegislatorTitle,
        getLegislatorEmail,
        getLegislatorEmailPreview,
        getLegislatorPhone,
        getLegislatorPhonePreview,
        handleCopy,
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
