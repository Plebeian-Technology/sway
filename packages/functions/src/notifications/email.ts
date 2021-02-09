import * as sendgrid from "@sendgrid/mail";
import {
    Collections,
    CONGRESS_LOCALE_NAME,
    NOTIFICATION_FREQUENCY,
    NOTIFICATION_TYPE,
} from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { isEmptyObject, titleize, createNotificationDate } from "@sway/utils";
import * as functions from "firebase-functions";
import { DocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import { fire, sway } from "sway";
import { db } from "../firebase";

const { logger } = functions;

export const sendSendgridEmail = async (
    locale: sway.ILocale | sway.IUserLocale | null | undefined,
    config: sway.IPlainObject,
    emails: string[] | string,
    templateId: string,
    cc?: string | string[],
    data?: sway.IPlainObject,
): Promise<boolean> => {
    if (!locale) {
        throw new Error("no locale included when sending sendgrid email");
    }
    logger.info("Sending sendgrid email.");
    const localeName =
        locale.name === CONGRESS_LOCALE_NAME
            ? "Congress"
            : `${titleize(locale.city)}, ${locale.regionCode.toUpperCase()}`;

    const to =
        typeof emails === "string" ? emails : config.sendgrid.fromaddress;
    const bcc = typeof emails === "string" ? "" : emails;

    const additionalData = data ? data : {};
    sendgrid.setApiKey(config.sendgrid.apikey);
    const msg = {
        to,
        cc: cc || "",
        bcc,
        from: config.sendgrid.fromaddress,
        templateId: templateId,
        dynamicTemplateData: {
            localeName,
            ...additionalData,
        },
    };
    return sendgrid
        .send(msg)
        .then(([res]) => {
            logger.info(res);
            return res.statusCode < 300;
        })
        .catch((error) => {
            logger.error(error);
            return false;
        });
};

export const sendWelcomeEmail = (
    fireClient: SwayFireClient,
    config: sway.IPlainObject,
    email: string,
    success: boolean,
) => {
    if (!success) return;

    return sendSendgridEmail(
        fireClient.locale,
        config,
        email,
        config.sendgrid.welcometemplateid,
    ).then(() => true);
};

const mapUserEmailAddresses = (
    user: sway.IUser,
    sentEmails: string[] | undefined,
    fireClient: SwayFireClient,
    bill: sway.IBill,
    isNewBill: boolean,
) => {
    const localeName = fireClient.locale?.name;
    if (!localeName) return null;

    if (sentEmails?.includes(user.email)) {
        return null;
    }
    const userLocaleNames = user.locales.map((l) => l.name);
    if (!userLocaleNames.includes(localeName)) {
        return null;
    }
    if (isNewBill) {
        return user.email;
    }
    if (isUserAlreadyVoted(fireClient, user, bill)) {
        return null;
    }
    return user.email;
};

export const sendBotwEmailNotification = async (
    fireClient: SwayFireClient,
    config: sway.IPlainObject,
    bill: sway.IBill,
    isNewBill: boolean,
    sentEmails?: string[],
): Promise<string[]> => {
    const { locale } = fireClient;
    if (!locale) {
        throw new Error(
            "Locale is undefined on fireClient in sendBotwEmailNotification",
        );
    }
    const date = createNotificationDate();
    const notification = await fireClient.notifications().get(date);
    if (notification) {
        logger.error(
            `notification with date - ${date} - already exists for locale. Skipping email send.`,
        );
        return [];
    }

    logger.info("botw notification preparing email notification");
    const users = await usersToNotify(fireClient, [
        NOTIFICATION_TYPE.Email,
        NOTIFICATION_TYPE.EmailSms,
    ]);

    logger.info("botw notification collecting user emails");
    const emails =
        users &&
        !isEmptyObject(users) &&
        (users.map((user: sway.IUser) =>
            mapUserEmailAddresses(
                user,
                sentEmails,
                fireClient,
                bill,
                isNewBill,
            ),
        ) as string[]);
    if (!emails || isEmptyObject(emails)) {
        logger.error(
            "Could not map array of users to email addresses. Received users - ",
            users,
        );
        return [];
    }

    if (emails.length === 1 && emails[0] === config.sendgrid.fromaddress) {
        logger.info(
            "botw notification user emails are empty, sending to default email address -",
            config.sendgrid.fromaddress,
        );
    }

    logger.info("botw notification count of emails to send for locale -", emails.length, locale.name);
    logger.info("botw notification sending emails to -", emails);
    sendSendgridEmail(
        locale,
        config,
        emails.filter(Boolean),
        config.sendgrid.billoftheweektemplateid,
    )
        .then((isSent) => {
            if (isSent) {
                logger.info("creating new fire notification");
                fireClient.notifications().create(date);
            }
        })
        .catch(logger.error);
    return emails;
};

const usersToNotify = async (
    fireClient: SwayFireClient,
    notificationTypes: number[],
): Promise<sway.IUser[] | undefined> => {
    const settingsSnap: fire.TypedQuerySnapshot<sway.IUserSettings> = await fireClient
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

    const users = await getUsers(fireClient, settingsUids);
    if (!users) return;

    return users;
};

const getUsers = async (
    fireClient: SwayFireClient,
    uids: string[],
): Promise<sway.IUser[]> => {
    const locale = fireClient.locale;
    if (!locale) {
        throw new Error(
            "fireClient has no locale when getting users for email botw notification",
        );
    }
    const snaps = uids.map(async (uid: string) => {
        const user = await fireClient.users(uid).getWithoutAdminSettings();
        if (!user) return null;

        if (locale.name === CONGRESS_LOCALE_NAME) {
            return user;
        }

        const userLocaleNames = user.locales.map((l: sway.ILocale) => l.name);
        if (!userLocaleNames.includes(locale.name)) {
            return null;
        }

        return user;
    });
    const users = await Promise.all(snaps);
    return users.filter((u: sway.IUser | null) => !!u) as sway.IUser[];
};

const isUserAlreadyVoted = async (
    fireClient: SwayFireClient,
    user: sway.IUser,
    bill: sway.IBill,
): Promise<boolean> => {
    const locale = fireClient.locale;
    if (!locale) {
        throw new Error(
            "fireClient.locale is undefined in getNotVotedUserEmails",
        );
    }
    const doc = db.doc(userVoteDocumentPath(user.uid, locale, bill));
    const snap = await doc.get();
    return isUserVoted(snap);
};

const isUserVoted = (snap: DocumentSnapshot) => {
    return snap && snap.exists;
};

const userVoteDocumentPath = (
    uid: string,
    locale: sway.ILocale,
    bill: sway.IBill,
) => {
    return `${Collections.UserVotes}/${locale.name}/${uid}/${bill.firestoreId}`;
};
