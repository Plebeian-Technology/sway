/** @format */

import SwayFireClient from "@sway/fire";
import * as functions from "firebase-functions";
import { EventContext } from "firebase-functions";
import { QueryDocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import { sway } from "sway";
import { db, firestore } from "../firebase";

const { logger } = functions;

export const onInsertUserRegisterInvite = functions.firestore
    .document("users/{uid}")
    .onCreate((snapshot: QueryDocumentSnapshot, context: EventContext) => {
        const user: sway.IUser = snapshot.data() as sway.IUser;
        if (!user.invitedBy) return;

        logger.info("adding user invite uid to sender");

        const legis = new SwayFireClient(
            db,
            { name: user?.locale?.name } as sway.ILocale,
            firestore,
        );

        legis.userInvites(user.invitedBy).upsert(user.uid);
    });
