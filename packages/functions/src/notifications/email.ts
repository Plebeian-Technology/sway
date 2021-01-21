import * as sendgrid from "@sendgrid/mail";
import { NOTIFICATION_FREQUENCY, NOTIFICATION_TYPE } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import * as functions from "firebase-functions";
import { fire, sway } from "sway";
import { isEmptyObject } from "../utils";
import { sendSendgridEmail } from "../utils/email";

const { logger } = functions;

export const sendWelcomeEmail = (email: string, success: boolean) => {
    if (!success) return;

    return sendSendgridEmail(
        email,
        functions.config().sendgrid.welcometemplateid,
    ).then(() => true);
};

export const sendEmailNotification = async (fireClient: SwayFireClient) => {
    const config = functions.config();

    logger.info("preparing email notification");
    const users = await usersToNotify(fireClient, [
        NOTIFICATION_TYPE.Email,
        NOTIFICATION_TYPE.EmailSms,
    ]);

    logger.info("collecting user emails");
    const emails =
        users && !isEmptyObject(users)
            ? users.map((user: sway.IUser) => user.email)
            : [config.sendgrid.fromaddress];
    logger.info({ emails });
    logger.info("count of emails to send -", emails.length);

    sendgrid.setApiKey(config.sendgrid.apikey);

    const msg = {
        to: emails,
        from: config.sendgrid.fromaddress,
        templateId: config.sendgrid.templateid,
    };
    sendgrid.send(msg).then(logger.info).catch(logger.error);
};

const getUsers = async (
    legis: SwayFireClient,
    uids: string[],
): Promise<sway.IUser[]> => {
    const snaps = uids.map((uid: string) =>
        legis.users(uid).getWithoutAdminSettings(),
    );
    const users = await Promise.all(snaps);
    return users.filter((u: sway.IUser | void) => !!u) as sway.IUser[];
};

const usersToNotify = async (
    legis: SwayFireClient,
    notificationTypes: number[],
): Promise<sway.IUser[] | void> => {
    const settingsSnap: fire.TypedQuerySnapshot<sway.IUserSettings> = await legis
        .userSettings("taco")
        .where("notificationFrequency", "!=", NOTIFICATION_FREQUENCY.Off)
        .where("notificationType", "in", notificationTypes)
        .get();
    if (!settingsSnap) {
        logger.error("no user settings found to send notification to");
        return;
    }

    const settingsUids = settingsSnap.docs.map(
        (setting: fire.TypedQueryDocumentSnapshot<sway.IUserSettings>) =>
            setting.data().uid,
    );

    const users = await getUsers(legis, settingsUids);
    if (!users) return;

    return users;
};
