import sendgrid from "@sendgrid/mail";
import {
    Collections,
    CONGRESS_LOCALE_NAME,
    NOTIFICATION_FREQUENCY,
    NOTIFICATION_TYPE,
} from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { createNotificationDate, isEmptyObject, titleize } from "@sway/utils";
import * as functions from "firebase-functions";
import { DocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import { fire, sway } from "sway";
import { db } from "../firebase";

const { logger } = functions;

/**
 * Sends a sendgrid mail object
 * https://sendgrid.com/docs/api-reference/
 *
 * @param {sway.ILocale} locale
 * @param {sway.IPlainObject} config
 * @param {string[] | string} emails
 * @param {string} templateId
 * @param {string | string[]} cc
 * @param {object} replyTo
 * @param {sway.IPlainObject} data
 */
export const sendSendgridEmail = async (
    locale: sway.ILocale | sway.IUserLocale | null | undefined,
    config: sway.IPlainObject,
    emails: string[] | string,
    templateId: string,
    {
        data,
        cc,
        replyTo,
    }: {
        cc?: string | string[];
        data?: sway.IPlainObject;
        replyTo?: string;
    },
): Promise<boolean> => {
    if (!locale) {
        logger.error("no locale included when sending sendgrid email");
        return false;
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
    const msg: sendgrid.MailDataRequired = {
        to,
        bcc,
        from: config.sendgrid.fromaddress,
        templateId: templateId,
        dynamicTemplateData: {
            locale: locale.name,
            localeName,
            ...additionalData,
        },
    };
    if (cc) {
        msg.cc = cc;
    }
    if (replyTo) {
        msg.replyTo = replyTo;
    }
    return sendgrid
        .send(msg)
        .then(([res]) => {
            logger.info(res);
            return res.statusCode < 300;
        })
        .catch((error) => {
            logger.error(
                error,
                error?.response?.body,
                `Template ID - ${templateId}`,
            );
            return false;
        });
};

export const sendWelcomeEmail = (
    locale: sway.ILocale | sway.IUserLocale | null | undefined,
    config: sway.IPlainObject,
    email: string,
) => {
    if (!locale) {
        logger.error("locale is null or undefined in sendWelcomeEmail");
        return false;
    }

    return sendSendgridEmail(
        locale,
        config,
        email,
        config.sendgrid.welcometemplateid,
        {},
    ).then(() => true);
};

const mapUserEmailAddresses = async (
    user: sway.IUser,
    sentEmails: string[] | undefined,
    fireClient: SwayFireClient,
    bill: sway.IBill,
): Promise<string | null> => {
    const localeName = fireClient.locale?.name;
    if (!localeName) {
        logger.info("(map email) no locale name for user, skipping sending");
        return null;
    }
    if (sentEmails?.includes(user.email)) {
        logger.info(
            "(map email) user already received an email, skipping sending for locale -",
            localeName,
        );
        return null;
    }
    const userLocaleNames = user.locales.map((l) => l.name);
    if (!userLocaleNames.includes(localeName)) {
        logger.info(
            "(map email) user locales does not include locale, skipping sending for locale -",
            localeName,
        );
        return null;
    }
    if (!bill.isInitialNotificationsSent) {
        return user.email;
    }

    const isVoted = await isUserAlreadyVoted(fireClient, user, bill);
    if (isVoted) {
        logger.info(
            `(map email) user - ${user.uid} - already voted on bill - ${bill.firestoreId}, skipping sending for locale -`,
            localeName,
        );
        return null;
    }
    return user.email;
};

export const sendBotwEmailNotification = async (
    fireClient: SwayFireClient,
    config: sway.IPlainObject,
    bill: sway.IBill,
    sentEmails?: string[],
): Promise<string[]> => {
    const { locale } = fireClient;
    if (!locale) {
        logger.error(
            "locale is undefined on fireClient in sendBotwEmailNotification",
        );
        return [];
    }
    const date = createNotificationDate();
    const notification = await fireClient.notifications().get(date);
    if (notification) {
        logger.error(
            `notification with date - ${date} - already exists for locale - ${locale.name}. Skipping email send.`,
        );
        return [];
    }

    logger.info(
        "botw notification preparing email notification for locale -",
        locale.name,
    );
    const users = await usersToNotify(fireClient, [
        NOTIFICATION_TYPE.Email,
        NOTIFICATION_TYPE.EmailSms,
    ]);
    if (!users || isEmptyObject(users)) {
        logger.error("no user emails to notify for locale -", locale.name);
        return [];
    }

    logger.info(
        "botw notification collecting user emails for locale -",
        locale.name,
    );
    const promises: Promise<string | null>[] = users.map((user: sway.IUser) =>
        mapUserEmailAddresses(user, sentEmails, fireClient, bill),
    );
    const _emails = (await Promise.all(promises)) as (string | null)[];
    const emails = _emails.filter(Boolean) as string[];

    if (isEmptyObject(emails)) {
        logger.error(
            "Mapped emails from list of users is empty. All users may have voted already, or already received an email today. Skipping send for locale -",
            locale.name,
        );
        return [];
    }

    if (emails.length === 1 && emails[0] === config.sendgrid.fromaddress) {
        logger.info(
            "botw notification user emails are empty, sending to default email address and locale -",
            config.sendgrid.fromaddress,
            locale.name,
        );
    }

    logger.info(
        "botw notification count of emails to send for locale -",
        emails.length,
        locale.name,
    );
    logger.info("botw notification sending emails to -", emails);
    sendSendgridEmail(
        locale,
        config,
        emails.filter(Boolean),
        config.sendgrid.billoftheweektemplateid,
        {},
    )
        .then((isSent) => {
            if (isSent) {
                logger.info(
                    "creating new fire notification for locale -",
                    locale.name,
                );
                try {
                    fireClient.notifications().create(date);
                } catch (error) {
                    logger.error(error);
                }
            }
        })
        .catch(logger.error);
    return emails;
};

const usersToNotify = async (
    fireClient: SwayFireClient,
    notificationTypes: number[],
): Promise<sway.IUser[]> => {
    const isNotSunday = new Date().getDay() !== 0;
    if (isNotSunday) {
        logger.info("It's not Sunday. Getting only users with daily setting.");
    } else {
        logger.info(
            "It is Sunday. Getting all users without notifications off including daily and weekly users.",
        );
    }
    const settingsSnap = (await fireClient
        .userSettings("taco")
        .where(
            "notificationFrequency",
            isNotSunday ? "==" : "!=",
            isNotSunday
                ? NOTIFICATION_FREQUENCY.Daily
                : NOTIFICATION_FREQUENCY.Off,
        )
        .where("notificationType", "in", notificationTypes)
        .get()) as fire.TypedQuerySnapshot<sway.IUserSettings>;

    if (!settingsSnap || settingsSnap.empty) {
        logger.error(
            "no user settings found to send notification to for locale -",
            fireClient.locale?.name,
        );
        return [];
    }

    const settingsUids = settingsSnap.docs.map(
        (setting: fire.TypedQueryDocumentSnapshot<sway.IUserSettings>) =>
            setting.data().uid,
    );

    const users = await getUsers(fireClient, settingsUids);
    if (!users) return [];

    return users;
};

const getUsers = async (
    fireClient: SwayFireClient,
    uids: string[],
): Promise<sway.IUser[]> => {
    const locale = fireClient.locale;
    if (!locale) {
        logger.error(
            "fireClient has no locale when getting users for email botw notification",
        );
        return [];
    }
    const snaps = uids.map(async (uid: string) => {
        const user = await fireClient.users(uid).getWithoutSettings();
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
        logger.error("fireClient.locale is undefined in isUserAlreadyVoted");
        return true;
    }
    // const data = await fireClient.userVotes(user.uid).get(bill.firestoreId);
    // logger.info("USER VOTE DATA FOR BILL - ", bill.firestoreId, {data})
    // return isEmptyObject(data);
    const doc = db.doc(userVoteDocumentPath(user.uid, locale, bill));
    const snap = await doc.get();
    return isUserVoted(snap);
};

const isUserVoted = (snap: DocumentSnapshot): boolean => {
    return Boolean(snap && snap.exists);
};

const userVoteDocumentPath = (
    uid: string,
    locale: sway.ILocale,
    bill: sway.IBill,
) => {
    logger.info(
        "Checking for user vote at path -",
        `${Collections.UserVotes}/${locale.name}/${uid}/${bill.firestoreId}`,
    );
    return `${Collections.UserVotes}/${locale.name}/${uid}/${bill.firestoreId}`;
};
