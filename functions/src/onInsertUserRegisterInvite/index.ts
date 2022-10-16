/** @format */

import SwayFireClient from "@sway/fire";
import * as functions from "firebase-functions";
import { EventContext } from "firebase-functions";
import { QueryDocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import { sway } from "sway";
import { db, firestoreConstructor } from "../firebase";

const { logger } = functions;

export const onInsertUserRegisterInvite = functions.firestore
    .document("users/{uid}")
    .onCreate((snapshot: QueryDocumentSnapshot, context: EventContext) => {
        const user: sway.IUser = snapshot.data() as sway.IUser;
        if (!user.invitedBy) return;

        const fireClient = new SwayFireClient(db, null, firestoreConstructor, logger);

        logger.info("Redeeming user invite");
        return fireClient
            .userInvites(user.invitedBy)
            .upsert({
                redeemedNewUserUid: user.uid,
            })
            .then(() => {
                logger.info(
                    `New user - ${user.uid} - REDEEMED invite from user/sender - ${user.invitedBy}`,
                );
            })
            .catch(logger.error);
    });
