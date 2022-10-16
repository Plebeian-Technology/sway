/** @format */
import { Collections } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { findLocale, get } from "@sway/utils";
import * as functions from "firebase-functions";
import { Change, EventContext } from "firebase-functions";
import { QueryDocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import { sway } from "sway";
import { db, firestoreConstructor } from "../firebase";

const { logger } = functions;

export const onUserBillShareUpdateTotal = functions.firestore
    .document(`/${Collections.UserBillShares}/{locale}/{uid}/{billFirestoreId}`)
    .onUpdate(async (change: Change<QueryDocumentSnapshot>, _context: EventContext) => {
        const before: sway.IUserBillShare = change.before.data() as sway.IUserBillShare;
        const after: sway.IUserBillShare = change.after.data() as sway.IUserBillShare;

        const uid = change.after.ref.parent?.id;
        if (uid === "total") return;

        const localeName = change.after.ref.parent.parent?.id;
        if (!uid || !localeName) {
            logger.error("could not get uid or locale name, skipping update");
            logger.error("change.after.ref.id", change.after.ref.id);
            logger.error("change.after.ref.parent.id", change.after.ref.parent.id);
            return;
        }

        logger.info(
            `user bill share created for bill - ${after.billFirestoreId}, runing update of total scores`,
        );
        const locale = findLocale(localeName);
        if (!locale) {
            logger.error(
                "Skipping update of total shares. Could not find locale with name: ",
                localeName,
            );
            return;
        }

        const fireClient = new SwayFireClient(db, locale, firestoreConstructor, logger);
        const current = await fireClient.userBillShares("total").get(after.billFirestoreId);
        if (!current) {
            logger.error(
                `Skipping update, total user shares does not exist for bill - ${after.billFirestoreId}. It should be created in onUserBillShareCreateTotal`,
            );
            return;
        }

        const platformUpdated = Object.keys(after.platforms).find((key: string) => {
            return get(before.platforms, key) !== get(after.platforms, key);
        }) as sway.TSharePlatform;

        if (!platformUpdated) {
            logger.error("Platform share values are the same in before/after. Skipping update.");
            logger.error("Before -", before.platforms);
            logger.error("Before -", after.platforms);
            return;
        }

        logger.info(
            `updating total bill shares for bill - ${after.billFirestoreId} - for platform - ${platformUpdated}`,
        );
        fireClient
            .userBillShares("total")
            .update({
                billFirestoreId: after.billFirestoreId,
                platform: platformUpdated,
                uid: uid,
            })
            .catch(logger.error);
    });
