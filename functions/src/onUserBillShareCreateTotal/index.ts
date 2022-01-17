/** @format */
import { Collections } from "src/constants";
import SwayFireClient from "src/fire";
import { findLocale } from "src/utils";
import * as functions from "firebase-functions";
import { EventContext } from "firebase-functions";
import { QueryDocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import { sway } from "sway";
import { db, firestore } from "src/firebase";

const { logger } = functions;

export const onUserBillShareCreateTotal = functions.firestore
    .document(`/${Collections.UserBillShares}/{locale}/{uid}/{billFirestoreId}`)
    .onCreate(
        async (snapshot: QueryDocumentSnapshot, context: EventContext) => {
            const ref = snapshot.ref;
            const share = snapshot.data() as sway.IUserBillShare;

            const localeName = ref?.parent?.parent?.id;
            logger.info(
                `user bill share created for bill - ${share.billFirestoreId}, runing update of total scores`,
            );

            if (!localeName) {
                logger.error("could not get locale name, skipping update");
                logger.error("ref.id", ref.id);
                logger.error("ref.parent.id", ref.parent.id);
                return;
            }
            const locale = findLocale(localeName);
            if (!locale) {
                logger.error(
                    "Skipping update of total shares. Could not find locale with name: ",
                    localeName,
                );
                return;
            }

            const fireClient = new SwayFireClient(db, locale, firestore);

            const current = await fireClient
                .userBillShares("total")
                .get(share.billFirestoreId);

            if (!current) {
                logger.info(
                    `creating total user bill share from user shares for bill - ${share.billFirestoreId}`,
                );
                logger.info("user platform shares -", share.platforms);
                fireClient
                    .userBillShares("total")
                    .create({
                        billFirestoreId: share.billFirestoreId,
                        platforms: { ...share.platforms },
                        uids: share.uids,
                    } as sway.IUserBillShare)
                    .catch(logger.error);
            }
        },
    );
