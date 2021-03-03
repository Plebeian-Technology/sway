/** @format */

import { Collections, INITIAL_SHARE_PLATFORMS } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { findLocale, isNotUsersLocale, userLocaleFromLocales } from "@sway/utils";
import * as functions from "firebase-functions";
import { EventContext } from "firebase-functions";
import { QueryDocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import { fire, sway } from "sway";
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
                .get()) as sway.IUserWithSettings;
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

            const representatives = await fireClient
                .legislators()
                .representatives(
                    uid,
                    userLocale.district,
                    user.regionCode,
                    bill.active,
                );
            if (!representatives || representatives.length === 0) {
                logger.error(`no representatives found for user - ${uid}`);
                return false;
            }

            representatives.forEach(
                async (
                    legislator: sway.ILegislatorWithUserScore | undefined,
                ) => {
                    if (!legislator) {
                        logger.error(
                            `representative is undefined on bill ${billFirestoreId}`,
                        );
                        return;
                    }

                    const legislatorVote:
                        | sway.ILegislatorVote
                        | undefined = await fireClient
                        .legislatorVotes()
                        .get(legislator.legislator.externalId, billFirestoreId);
                    if (!legislatorVote) {
                        logger.warn(
                            "legislatorVote is falsey, proceeding with userLegislatorVotes update/create",
                        );
                    }

                    const userLegislatorVoteRef:
                        | fire.TypedDocumentReference<sway.IUserLegislatorVote>
                        | undefined = await fireClient
                        .userLegislatorVotes(uid)
                        .create(
                            support,
                            legislatorVote && legislatorVote.support,
                            billFirestoreId,
                            legislator.legislator.externalId,
                        );
                    if (!userLegislatorVoteRef) {
                        logger.error(
                            `skipping update of legislator scores because, could not create user/legislator vote for user - ${uid}. returns undefined when updating existing doc and legislatorVote is falsey`,
                        );
                        return;
                    }

                    logger.info("updating user/legislator score on bill");
                    logger.info(`user: ${uid}`);
                    logger.info(`bill: ${billFirestoreId}`);
                    logger.info(
                        `legislator: ${legislator.legislator.externalId}`,
                    );
                    fireClient
                        .userLegislatorScores()
                        .update(
                            legislator.legislator,
                            legislatorVote,
                            doc,
                            userLegislatorVoteRef.path,
                            uid,
                        );
                    fireClient
                        .userDistrictScores()
                        .update(
                            legislator.legislator,
                            legislatorVote,
                            doc,
                            userLegislatorVoteRef.path,
                        );
                },
            );

            const path = snapshot.ref.path;
            const now = firestore.FieldValue.serverTimestamp();

            logger.info("user vote insert - update bill scores");
            await fireClient.billScores().update(billFirestoreId, support);

            if (userLocale.district) {
                logger.info(
                    "updating district score for district -",
                    userLocale.district,
                );
                await fireClient
                    .billScores()
                    .updateDistrictScores(
                        billFirestoreId,
                        support,
                        userLocale.district,
                    );
            }

            logger.info("updating district score for district - 0");
            await fireClient
                .billScores()
                .updateDistrictScores(billFirestoreId, support, 0);

            logger.info("update bill with new user vote path");
            await fireClient.bills().update(doc, {
                updatedAt: now,
                userVotePaths: firestore.FieldValue.arrayUnion(path),
            });

            return true;
        },
    );
