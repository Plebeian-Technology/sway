import { usePage } from "@inertiajs/react";
import { useLocale } from "app/frontend/hooks/useLocales";
import { useUser } from "app/frontend/hooks/users/useUser";
import { EXECUTIVE_BRANCH_TITLES, IS_DEVELOPMENT, Support } from "app/frontend/sway_constants";
import { getFullUserAddress, isAtLargeLegislator, titleize } from "app/frontend/sway_utils";
import { formatPhone } from "app/frontend/sway_utils/phone";
import { sway } from "sway";

export const useContactLegislator = (
    legislator: sway.ILegislator | undefined,
    user_vote: sway.IUserVote,
    type: "email" | "phone" = "email",
) => {
    const user = useUser();
    const [locale] = useLocale();
    const bill = usePage().props.bill as sway.IBill;

    if (!legislator) {
        return null;
    }

    const fullAddress = (): string => {
        return user.address?.full_address || getFullUserAddress(user);
    };

    const registeredVoter = (): string => {
        if (!user.is_registered_to_vote) {
            return "I";
        }
        return "I am registered to vote and";
    };

    const shortSupport = (): string => {
        if (!user_vote) return "";

        if (user_vote.support === Support.For) {
            return "support";
        }
        return "oppose";
    };

    const longSupport = (): string => {
        if (!user_vote) return "";

        if (EXECUTIVE_BRANCH_TITLES.includes(legislator.title.toLowerCase())) {
            return shortSupport();
        }
        if (user_vote.support === Support.For) {
            return "vote in support of";
        }
        return `vote ${Support.Against}`;
    };

    const residence = (): string => {
        if (isAtLargeLegislator(legislator.district)) {
            return `in ${titleize(locale.city)}`;
        }
        return `in your district`;
    };

    const getLegislatorTitle = (): string => {
        if (legislator.title?.toLowerCase() === "councilmember") {
            return "Council Member";
        }
        return legislator.title;
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
            return `(dev) ${formatPhone("1234567890")} - (prod) ${formatPhone(legislator.phone)}`;
        }
        return formatPhone(legislator.phone);
    };

    const userVoteText = () =>
        user_vote
            ? `Please ${longSupport()} bill ${bill.external_id} - ${bill.title}.\n\r`
            : `I am ${
                  type === "phone" ? "calling" : "writing"
              } to you today because I would like you to support... {NAME OF BILL}.\n\r`;

    const defaultMessage = `Hello ${getLegislatorTitle()} ${legislator.last_name}, my name is ${user.full_name ?? "{YOUR_NAME}"} and ${registeredVoter()} reside ${residence()}${fullAddress() ? " at " + fullAddress() : ""}.\n\r${userVoteText()}\n\rThank you, ${user.full_name ?? "{YOUR_NAME}"}`;

    return {
        defaultMessage,
        fullAddress,
        registeredVoter,
        shortSupport,
        longSupport,
        residence,
        userVoteText,
        getLegislatorTitle,
        getLegislatorEmail,
        getLegislatorEmailPreview,
        getLegislatorPhone,
        getLegislatorPhonePreview,
    };
};
