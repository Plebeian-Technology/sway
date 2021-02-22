/** @format */

import SwayFireClient from "@sway/fire";
import * as functions from "firebase-functions";
import { EventContext } from "firebase-functions";
import { QueryDocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import { sway } from "sway";
import { db, firestore } from "../firebase";
import { findLocale } from "@sway/utils";

const { logger } = functions;

export const onInsertUserRegisterInvite = functions.firestore
    .document("users/{uid}")
    .onCreate((snapshot: QueryDocumentSnapshot, context: EventContext) => {
        const user: sway.IUser = snapshot.data() as sway.IUser;
        if (!user.invitedBy) return;

        logger.info("Adding user invite uid to sender");
        const localeName = user?.locales[0]?.name;
        if (!localeName) {
            logger.error(
                "User sending invite is missing locales. Skipping invite.",
            );
            return;
        }
        const locale = findLocale(localeName);
        if (!locale) {
            logger.error(
                `Locale with name - ${localeName} - not in LOCALES. Skipping user registration from invite.`,
            );
            return;
        }

        const fireClient = new SwayFireClient(db, locale, firestore);

        fireClient.userInvites(user.invitedBy).upsert({
            redeemedNewUserUid: user.uid
        });
    });
