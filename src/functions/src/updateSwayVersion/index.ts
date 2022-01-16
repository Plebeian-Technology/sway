/** @format */

import { Collections } from "src/constants";
import * as functions from "firebase-functions";
import { Request, Response } from "firebase-functions";
import { db } from "../firebase";

const { logger } = functions;

export const updateSwayVersion = functions.https.onRequest(
    (req: Request, res: Response) => {
        const { version } = req.body;
        logger.info("Updating Sway version to be -", version);

        db.collection(Collections.SwayVersion)
            .doc("current")
            .update({
                version,
            })
            .then(() => {
                logger.info("Updated Sway version.");
                res.status(200).send({ success: true, version });
            })
            .catch((error) => {
                logger.info("Failed to update Sway version.");
                logger.error(error);
                res.status(200).send({ success: false, version });
            });
    },
);
