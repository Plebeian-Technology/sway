/** @format */

import { titleize } from "@sway/utils";
import * as functions from "firebase-functions";
import { CallableContext } from "firebase-functions/lib/providers/https";
import { sway } from "sway";
import { sendSendgridEmail } from "../notifications";
import { isEmptyObject } from "../utils";

const { logger } = functions;

interface IData {
    locale: sway.ILocale;
    sender: sway.IUser;
    emails: string[];
}

// onRequest for external connections like Express (req/res)
export const sendUserInvites = functions.https.onCall(
    async (data: IData, context: CallableContext): Promise<string> => {
        if (!context?.auth?.uid) {
            logger.error(
                "auth uid does not match data uid, skipping user sway aggregation",
            );
            return "Invalid Credentials.";
        }
        const { sender, locale, emails } = data;
        if (!locale) {
            logger.error("no locale received, skipping send");
            return "Invalid Credentials.";
        }
        if (!emails || isEmptyObject(emails)) {
            logger.error("no emails received, skipping send");
            return "No emails received.";
        }
        const config = functions.config();
        const sent = await sendSendgridEmail(
            locale,
            config,
            emails,
            config.sendgrid.invitetemplateid,
            sender.email,
            { uid: sender.uid, sender: titleize(sender.name) },
        );
        if (!sent) {
            return "Error sending invites.";
        }
        return "";
    },
);
