import { auth } from "firebase-admin";
import * as functions from "firebase-functions";
import { CallableContext } from "firebase-functions/lib/providers/https";

const { logger } = functions;

interface IData {
    uid: string;
    email: string;
}

// https://firebase.google.com/docs/auth/admin/create-custom-tokens#letting_the_admin_sdk_discover_a_service_account
export const getApiKey = functions.https.onCall(
    async (
        data: IData,
        context: CallableContext,
    ): Promise<string | undefined> => {
        if (context.auth?.token.email !== "dave@sway.vote") {
            logger.error(
                `getApiKey - context email is NOT dave@sway.vote. Skipping api key create.`,
            );
            return;
        }

        const { uid, email } = data;

        if (!uid) {
            logger.error(
                "getApiKey - no uid in data. Skipping api key create.",
            );
            return;
        }

        const verify = await auth().getUserByEmail(email);
        if (!verify || verify.uid !== uid) {
            logger.error(
                `getApiKey - uid of user with email - ${email} - is NOT the same as the uid from the request context. Context uid - ${uid} | Email uid - ${verify.uid}. Skipping API key create.`,
            );
            return;
        }

        return auth()
            .createCustomToken(uid, {
                billOfTheWeek: true,
            })
            .catch((error) => {
                logger.error(
                    `getApiKey - error creating custom token for uid - ${uid}. Error: `,
                    error,
                );
                return undefined;
            });
    },
);
