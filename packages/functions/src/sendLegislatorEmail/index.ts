/** @format */

import { SHARE_PLATFORMS } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { firestore } from "firebase-admin";
import * as functions from "firebase-functions";
import { CallableContext } from "firebase-functions/lib/providers/https";
import { sway } from "sway";
import { db } from "../firebase";
import { sendSendgridEmail } from "../notifications";

const { logger } = functions;

interface IData {
    locale: sway.ILocale;
    sender: sway.IUser;
    message: string;
    support: "support" | "oppose",
    legislatorEmail: string;
    billFirestoreId: string;
}

// onRequest for external connections like Express (req/res)
export const sendLegislatorEmail = functions.https.onCall(
    async (data: IData, context: CallableContext): Promise<string> => {
        if (!context?.auth?.uid) {
            logger.error(
                "auth uid does not match data uid, skipping user sway aggregation",
            );
            return "Invalid Credentials.";
        }
        const {
            sender,
            locale,
            message,
            support,
            legislatorEmail,
            billFirestoreId,
        } = data;
        if (!sender) {
            logger.error("no sender received, skipping send");
            return "Invalid Sender.";
        }
        if (!locale) {
            logger.error("no locale received, skipping send");
            return "Invalid Locale.";
        }
        if (!message) {
            logger.error("no message received, skipping send");
            return "Invalid Message.";
        }
        if (!legislatorEmail) {
            logger.error("no legislatorEmail received, skipping send");
            return "Invalid Receiver.";
        }
        if (!billFirestoreId) {
            logger.error("no billFirestoreId received, skipping send");
            return "Invalid Bill.";
        }

        const config = functions.config();
        return sendSendgridEmail(
            locale,
            config,
            legislatorEmail,
            config.sendgrid.legislatoremailtemplateid,
            {
                replyTo: sender.email,
                cc: sender.email,
                data: { message, support, billFirestoreId },
            },
        ).then((sent) => {
            if (!sent) {
                return "Error sending invites.";
            }
            const fireClient = new SwayFireClient(db, locale, firestore);
            return fireClient
                .userBillShares(sender.uid)
                .upsert({
                    billFirestoreId,
                    platform: SHARE_PLATFORMS.Email,
                    uid: sender.uid,
                })
                .then(() => {
                    return "";
                })
                .catch((error: Error) => {
                    logger.error(error);
                    return "Email sent but, error recording share.";
                });
        });
    },
);