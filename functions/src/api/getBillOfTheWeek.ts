import SwayFireClient from "@sway/fire";
import { auth } from "firebase-admin";
import * as functions from "firebase-functions";
import { Request, Response } from "firebase-functions";
import { sway } from "sway";
import { db, firestore } from "../firebase";

const { logger } = functions;

const response = (
    res: Response,
    status: number,
    success: boolean,
    message?: string,
    data?: sway.IBillOrgsUserVoteScore[],
): Response => {
    return res.status(status).json({
        success,
        message,
        data,
    });
};

// External access to Sway bill of the week
// https://firebase.google.com/docs/auth/admin/verify-id-tokens#web
export const getBillOfTheWeek = functions.https.onRequest(
    async (req: Request, res: Response): Promise<void> => {
        const token = req.headers["x-api-key"];

        if (!token) {
            logger.error(
                "api.getBillOfTheWeek - no token included as 'x-api-key' header in request.",
            );
            response(res, 200, false, "no token included as 'x-api-key' header in request.").send();
            return;
        }
        const authenticated = await auth().verifyIdToken(Array.isArray(token) ? token[0] : token);
        if (!authenticated) {
            response(res, 400, false).send();
            return;
        }

        const uid = authenticated.uid;

        const fireUserClient = new SwayFireClient(db, undefined, firestore);
        const user = await fireUserClient.users(uid).getWithoutSettings();

        if (!user || !user.locales) {
            response(
                res,
                200,
                false,
                "Could not find a user or locales associated with this api key. Do you have a Sway account?",
            ).send();
            return;
        }

        const withOrganizations = (client: SwayFireClient, bill: sway.IBill | undefined | void) => {
            if (!bill) return;
            return client.organizations().listPositions(bill.firestoreId);
        };

        const withScore = async (
            client: SwayFireClient,
            bill: sway.IBill | undefined | void,
        ): Promise<sway.IBillScore | undefined> => {
            if (!bill) return;
            return client.billScores().get(bill.firestoreId);
        };

        const bills = await Promise.all(
            user.locales.map(async (locale) => {
                const fireClient = new SwayFireClient(db, locale, firestore, logger);
                const bill = await fireClient.bills().ofTheWeek();
                if (!bill) return;

                const score = await withScore(fireClient, bill);
                const organizations = await withOrganizations(fireClient, bill);

                return {
                    bill,
                    organizations,
                    score,
                };
            }),
        ).catch(logger.error);

        const data = bills && (bills.filter(Boolean) as sway.IBillOrgsUserVoteScore[]);
        if (!data) {
            response(res, 200, false, "Could not find any bills of the week.").send();
            return;
        }

        response(
            res,
            200,
            true,
            `Sway bills of the week for - ${user.locales.map((l) => l.name).join(", ")}`,
            data,
        ).send();
        return;
    },
);
