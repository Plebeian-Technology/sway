import * as sendgrid from "@sendgrid/mail";
import * as functions from "firebase-functions";
const { logger } = functions;

export const sendSendgridEmail = async (emails: string[] | string, templateId: string) => {
    logger.info("sending sendgrid email");

    sendgrid.setApiKey(functions.config().sendgrid.apikey);
    const msg = {
        to: emails,
        from: functions.config().sendgrid.fromaddress,
        templateId: templateId,
    };
    return sendgrid.send(msg).then(logger.info).catch(logger.error);
};