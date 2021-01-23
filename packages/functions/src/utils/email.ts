import * as sendgrid from "@sendgrid/mail";
import * as functions from "firebase-functions";
const { logger } = functions;

export const sendSendgridEmail = async (email: string, templateId: string) => {
    logger.info("sending sendgrid email");
    const config = functions.config().sengrid

    sendgrid.setApiKey(config.apikey);
    const msg = {
        to: email,
        from: config.fromaddress,
        templateId: templateId,
    };
    return sendgrid.send(msg).then(logger.info).catch(logger.error);
};