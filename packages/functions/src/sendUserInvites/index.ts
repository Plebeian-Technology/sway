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

// onRequest for external connections like Express (req/res)
export const sendUserInvites = functions.https.onCall(
    async (data: IData, context: CallableContext): Promise<string> => {
        if (!context?.auth?.uid || context?.auth?.uid !== data?.sender?.uid) {
            logger.error(
                "auth uid does not match data uid, skipping send user invite",
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

        const fireClient = new SwayFireClient(db, locale, firestore);
        const toSend = await fireClient
            .userInvites("all_users")
            .isNotSentTo(emails);

        if (isEmptyObject(toSend)) {
            return "Already sent invites to all emails listed.";
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
            return "Error sending invites.";
        }
        return fireClient
            .userInvites("all_users")
            .upsert({ sentInviteToEmails: toSend })
            .then(() => {
                return fireClient
                    .userInvites(sender.uid)
                    .upsert({
                        sentInviteToEmails: toSend,
                    })
                    .then(() => {
                        return "";
                    })
                    .catch((error: Error) => {
                        logger.error(error);
                        return "";
                    });
            })
            .catch((error: Error) => {
                logger.error(error);
                return "";
            });
    },
);
