/** @format */

import { Collections, INITIAL_SHARE_PLATFORMS } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import {
    findLocale,
    isNotUsersLocale,
    userLocaleFromLocales,
} from "@sway/utils";
import * as functions from "firebase-functions";
import { EventContext } from "firebase-functions";
import { QueryDocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import { sway } from "sway";
import { db, firestore } from "../firebase";

const { logger } = functions;

export const onInsertUserVoteUpdateScore = functions.firestore
    .document(`${Collections.UserVotes}/{locale}/{uid}/{billFirestoreId}`)
    .onCreate(
        async (snapshot: QueryDocumentSnapshot, context: EventContext) => {
            logger.info("user vote created, running score update function");

            const doc: sway.IUserVote = snapshot.data() as sway.IUserVote;
            if (!doc) {
                logger.error("no user vote");
                return false;
            }

            const { support } = doc;
            if (!support) {
                logger.error("user vote is missing support");
                return false;
            }

            const billFirestoreId = snapshot.ref.id;
            const uid = snapshot.ref.parent.id;
            const localeName = snapshot.ref.parent.parent?.id;
            if (!localeName) {
                logger.error("could not get locale name, skipping update");
                logger.error("snap.ref", snapshot.ref.id);
                logger.error("snapshot.ref.parent.id", snapshot.ref.parent.id);
                return;
            }
            const locale = findLocale(localeName);
            if (!locale) {
                logger.error(
                    `Locale with name - ${localeName} - not in LOCALES. Skipping user vote score update.`,
                );
                return;
            }

            logger.info("user vote create update function");
            logger.info(`billFirestoreId - ${billFirestoreId}`);
            logger.info(`uid - ${uid}`);
            logger.info(`localeName - ${localeName}`);

            const fireClient = new SwayFireClient(db, locale, firestore);
            const bill = await fireClient.bills().get(billFirestoreId);
            if (!bill) {
                logger.error(
                    `no bill found with billFirestoreId - ${billFirestoreId} - in locale - ${localeName}. Skipping user vote score updates.`,
                );
                return false;
            }

            const userWithSettings = (await fireClient
                .users(uid)
                .getWithSettings()) as sway.IUserWithSettings;
            if (!userWithSettings) {
                logger.error("could not find user");
                return false;
            }
            const user = userWithSettings.user;
            const userLocale = userLocaleFromLocales(user, localeName);
            if (!userLocale || isNotUsersLocale(user, userLocale)) {
                logger.error("user locale !== bill locale");
                logger.error(`user locale - ${userLocale}`);
                logger.error(`bill locale - ${localeName}`);
                return false;
            }

            const createUserBillShares = async () => {
                logger.info("creating initial user bill shares");
                await fireClient
                    .userBillShares(uid)
                    .create({
                        billFirestoreId,
                        uids: [uid],
                        platforms: INITIAL_SHARE_PLATFORMS,
                    })
                    .catch(logger.error);
            };

            await createUserBillShares();

            logger.info(
                "updating bill score with district -",
                userLocale.district,
            );
            await fireClient
                .billScores()
                .update(billFirestoreId, support, userLocale.district);

            return true;
        },
    );
