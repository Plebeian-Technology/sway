/** @format */

import SwayFireClient from "@sway/fire";
import { titleize } from "@sway/utils";
import { firestore } from "firebase-admin";
import * as functions from "firebase-functions";
import { CallableContext } from "firebase-functions/lib/providers/https";
import { sway } from "sway";
import { db } from "../firebase";
import { sendSendgridEmail } from "../notifications";
import { IFunctionsConfig, isEmptyObject } from "../utils";

const { logger } = functions;

interface IData {
    locale: sway.ILocale;
    sender: sway.IUser;
    emails: string[];
}

interface ISentInvitesResponseData {
    sent: string[];
    rejected: string[];
}

// onRequest for external connections like Express (req/res)
export const sendUserInvites = functions.https.onCall(
    async (data: IData, context: CallableContext): Promise<string | ISentInvitesResponseData> => {
        if (!context?.auth?.uid || context?.auth?.uid !== data?.sender?.uid) {
            logger.error("auth uid does not match data uid, skipping send user invite");
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

        const fireClient = new SwayFireClient(db, locale, firestore, logger);

        logger.info("Checking for user invites already sent to email addesses - ", emails);
        const _toSend = await fireClient.userInvites(sender.uid).getNotSentTo(emails);

        if (isEmptyObject(_toSend)) {
            logger.error("No valid email addresses to send, returning error message to user.");
            return "You have already sent invites to all of these email addresses.";
        }

        logger.info("Checking for existing users with emails in list - ", _toSend);
        const existingUsers = await fireClient.users("taco").where("email", "in", _toSend).get();
        const existingEmails = existingUsers.docs.map((u) => (u.data() as sway.IUser).email);

        logger.info(
            "Filtering out emails for existing users from toSend. Received existing emails - ",
            existingEmails,
        );
        const toSend = _toSend.filter((e) => !existingEmails.includes(e));
        if (isEmptyObject(toSend)) {
            logger.error("No valid email addresses to send, returning error message to user.");
            return "Could not send invites. Do the people you are inviting use Sway already?";
        }

        const config = functions.config() as IFunctionsConfig;
        const sent = await sendSendgridEmail(
            locale,
            config,
            toSend,
            config.sendgrid.invitetemplateid,
            {
                cc: sender.email,
                data: { uid: sender.uid, sender: titleize(sender.name) },
            },
        );
        if (!sent) {
            logger.error("sendSengridEmail returned false. Returning error message to user.");
            return "Error sending invites.";
        }
        return fireClient
            .userInvites(sender.uid)
            .upsert({
                sentInviteToEmails: toSend,
            })
            .then(() => {
                return {
                    sent: toSend,
                    rejected: emails.filter((e) => !toSend.includes(e)),
                };
            })
            .catch((error: Error) => {
                logger.error(error);
                return "Error recording invites.";
            });
    },
);