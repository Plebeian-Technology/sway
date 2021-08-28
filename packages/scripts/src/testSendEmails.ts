import * as sendgrid from "@sendgrid/mail";
import {
    BALTIMORE_CITY_LOCALE_NAME,
    CONGRESS_LOCALE_NAME,
} from "@sway/constants";
import { findLocale, titleize } from "@sway/utils";
import { sample } from "lodash";

const EMAILS = [
    "erewald@gmail.com",
    "dave@sway.vote",
    "dcordz@pm.me",
    "dave@lobbie.com",
    "dave@legisme.org",
];
// const LOCALE_NAME = CONGRESS_LOCALE_NAME;
const LOCALE_NAME = BALTIMORE_CITY_LOCALE_NAME;
const LOCALE = findLocale(LOCALE_NAME);
if (!LOCALE) {
    throw new Error(
        `findLocale did not return a valid locale from name - ${LOCALE_NAME}`,
    );
}

const SENDGRID_API_KEY = process.env.SENDGRID_API_KEY || "";
const SENDGRID_FROM_ADDRESS = process.env.SENDGRID_FROM_ADDRESS || "";
const SENDGRID_WELCOME_TEMPLATE_ID =
    process.env.SENDGRID_WELCOME_TEMPLATE_ID || "";
const SENDGRID_BILL_OF_THE_WEEK_TEMPLATE_ID =
    process.env.SENDGRID_BILL_OF_THE_WEEK_TEMPLATE_ID || "";

const sendSendgridEmail = async (
    emails: string[] | string,
    templateId: string,
) => {
    console.log("sending sendgrid email");
    const localeName =
        LOCALE.name === CONGRESS_LOCALE_NAME
            ? "Congress"
            : `${titleize(LOCALE.city)}, ${LOCALE.regionCode.toUpperCase()}`;

    const to = typeof emails === "string" ? emails : SENDGRID_FROM_ADDRESS;
    const bcc = typeof emails === "string" ? "" : emails;

    sendgrid.setApiKey(SENDGRID_API_KEY);
    const msg = {
        to,
        bcc,
        from: SENDGRID_FROM_ADDRESS,
        templateId: templateId,
        dynamicTemplateData: {
            localeName,
        },
    };
    return sendgrid
        .send(msg)
        .then(console.log)
        .catch((error) => console.dir(error, { depth: null }));
};

export const sendWelcomeEmail = () => {
    const email = sample(EMAILS) || "";
    console.log("SENDING WELCOME EMAIL TO -", email);

    return sendSendgridEmail(email, SENDGRID_WELCOME_TEMPLATE_ID).then(
        () => true,
    );
};

export const sendBotwEmailNotification = () => {
    console.log("SENDING BOTW NOTIFICATION EMAIL TO -", EMAILS);
    sendSendgridEmail(
        EMAILS.filter(Boolean),
        SENDGRID_BILL_OF_THE_WEEK_TEMPLATE_ID,
    ).then(() => true);
};

// sendWelcomeEmail();
sendBotwEmailNotification();
