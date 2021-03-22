import {
    Collections,
    NOTIFICATION_FREQUENCY,
    NOTIFICATION_TYPE,
} from "@sway/constants";
import * as functions from "firebase-functions";
import { Request, Response } from "firebase-functions";
import { sway } from "sway";
import MessagingResponse from "twilio/lib/twiml/MessagingResponse";
import { db } from "../firebase";

const { logger } = functions;

export const smsResponse = functions.https.onRequest(
    async (req: Request, res: Response) => {
        const { From, Body }: { From: string; Body: string } = req.body;
        logger.info(
            "Received twilio message with data -",
            JSON.stringify(req.body, null, 4),
        );

        const sendSuccessResponse = () => {
            logger.info("Preparing STOP response message.");
            const twiml = new MessagingResponse();
            twiml.message(
                "Got it! Sway won't send you any more messages. If you'd like to opt-in in the future you can update your settings through Sway.",
            );
            res.writeHead(200, { "Content-Type": "text/xml" });
            res.end(twiml.toString());
        };

        const sendFailureResponse = (message?: string) => {
            logger.info("Preparing FAILURE response message.");
            const twiml = new MessagingResponse();
            twiml.message(
                message ||
                    "Whoops, looks like we had an issue updating your profile. We're looking into it but in the meantime you can change your settings through Sway.\n\rhttps://app.sway.vote/settings",
            );
            res.writeHead(200, { "Content-Type": "text/xml" });
            res.end(twiml.toString());
        };

        if (Body && Body.toLowerCase() === "stop") {
            const _from = From.replace("+1", "").replace(/\D/, "");
            const from = _from.length === 11 ? _from.slice(1) : _from;

            const uid: string | void = await db
                .collection(Collections.Users)
                .where("phone", "==", from)
                .get()
                .then((snaps) => {
                    return (snaps.docs.map((d) => d.data()) as sway.IUser[])[0]
                        .uid;
                })
                .catch(logger.error);
            if (!uid) {
                logger.error(
                    "Could not find User/UID from Phone -",
                    JSON.stringify(
                        {
                            _from,
                            from,
                            From,
                        },
                        null,
                        4,
                    ),
                );
                return sendFailureResponse();
            }

            const settingsRef = db
                .collection(Collections.UserSettings)
                .doc(uid);

            settingsRef.get().then((snap) => {
                const settings = snap.data() as sway.IUserSettings;
                if (settings.notificationType === NOTIFICATION_TYPE.Sms) {
                    settingsRef
                        .update({
                            notificationType: NOTIFICATION_TYPE.None,
                            notificationFrequency: NOTIFICATION_FREQUENCY.Off,
                        })
                        .then(sendSuccessResponse)
                        .catch(sendFailureResponse);
                } else {
                    settingsRef
                        .update({
                            notificationType: NOTIFICATION_TYPE.Email,
                        })
                        .then(sendSuccessResponse)
                        .catch(sendFailureResponse);
                }
            });
        } else {
            sendFailureResponse(
                "Sorry, Sway doesn't know how to process that. STOP, Stop and stop are all valid if you no longer want to receive updates through SMS/Text messages.",
            );
        }
    },
);
