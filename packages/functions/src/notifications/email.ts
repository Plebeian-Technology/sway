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
import { IFunctionsConfig } from "../utils";

const { logger } = functions;

/**
 * Sends a sendgrid mail object
 * https://sendgrid.com/docs/api-reference/
 *
 * @param {sway.ILocale} locale
 * @param {IFunctionsConfig} config
 * @param {string[] | string} emails
 * @param {string} templateId
 * @param {string | string[]} cc
 * @param {object} replyTo
 * @param {sway.IPlainObject} data
 */
export const sendSendgridEmail = async (
    locale: sway.ILocale | sway.IUserLocale | null | undefined,
    config: IFunctionsConfig,
    emails: string[] | string,
    templateId: string,
    {
        data,
        cc,
        replyTo,
        isdevelopment,
    }: {
        cc?: string | string[];
        data?: sway.IPlainObject;
        replyTo?: string;
        isdevelopment?: string | boolean;
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

    if (isdevelopment && (isdevelopment === "true" || isdevelopment === true)) {
        logger.info(
            "IS DEVELOPMENT SKIPPING SEND EMAIL. SENDGRID MESSAGE - ",
            JSON.stringify({ msg }, null, 4),
        );
        return true;
    }

    logger.info(
        "Calling sengrid.send with msg - ",
        JSON.stringify({ msg }, null, 4),
    );
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
    config: IFunctionsConfig,
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
    locale: sway.ILocale,
    user: sway.IUser,
    bill: sway.IBill,
    sentEmails: string[],
): Promise<string | null> => {
    if (sentEmails.includes(user.email)) {
        logger.info(
            "(map email) user already received an email, skipping sending for locale -",
            locale.name,
        );
        return null;
    }
    const userLocaleNames = user.locales.map((l) => l.name);
    if (!userLocaleNames.includes(locale.name)) {
        logger.info(
            "(map email) user locales does not include locale, skipping sending for locale -",
            locale.name,
        );
        return null;
    }
    if (!bill.isInitialNotificationsSent) {
        return user.email;
    }

    const isVoted = await isUserAlreadyVoted(locale, user, bill);
    if (isVoted) {
        logger.info(
            `(map email) user - ${user.uid} - already voted on bill - ${bill.firestoreId}, skipping sending for locale -`,
            locale.name,
        );
        return null;
    }
    return user.email;
};

export const sendBotwEmailNotification = async (
    fireClient: SwayFireClient,
    locale: sway.ILocale,
    config: IFunctionsConfig,
    bill: sway.IBill,
    sentEmails: string[],
): Promise<string[]> => {
    const date = createNotificationDate();
    const notification = await fireClient.notifications().get(date);
    if (notification) {
        logger.error(
            `notification with date - ${date} - already exists for locale - ${locale.name}. Skipping email send.`,
        );
        return sentEmails || [];
    }

    logger.info(
        "botw notification preparing email notification for locale -",
        locale.name,
    );
    const users = await usersToNotify(fireClient, locale, [
        NOTIFICATION_TYPE.Email,
        NOTIFICATION_TYPE.EmailSms,
    ]);
    if (!users || isEmptyObject(users)) {
        logger.error("no user emails to notify for locale -", locale.name);
        return sentEmails || [];
    }

    logger.info(
        "botw notification collecting user emails for locale -",
        locale.name,
    );
    const promises: Promise<string | null>[] = users.map((user: sway.IUser) =>
        mapUserEmailAddresses(locale, user, bill, sentEmails),
    );
    const _emails = (await Promise.all(promises)) as (string | null)[];
    const emails = _emails.filter(Boolean) as string[];

    if (isEmptyObject(emails)) {
        logger.error(
            "Mapped emails from list of users is empty. All users may have voted already, or already received an email today. Skipping send for locale -",
            locale.name,
        );
        return sentEmails || [];
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
    logger.info(
        `botw notification sending emails for locale - ${locale.name} - to -`,
        emails,
    );

    sendSendgridEmail(
        locale,
        config,
        emails.filter(Boolean),
        config.sendgrid.billoftheweektemplateid,
        { isdevelopment: config.sway.isdevelopment },
    )
        .then((isSent) => {
            if (!isSent) return;
            logger.info(
                "creating new fire notification for locale -",
                locale.name,
            );
            try {
                fireClient.notifications().create(date);
            } catch (error) {
                logger.error(error);
            }
        })
        .catch(logger.error);
    return emails;
};

const usersToNotify = async (
    fireClient: SwayFireClient,
    locale: sway.ILocale,
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

    const users = await getUsers(fireClient, locale, settingsUids);
    if (!users) return [];

    return users;
};

const getUsers = async (
    fireClient: SwayFireClient,
    locale: sway.ILocale,
    uids: string[],
): Promise<sway.IUser[]> => {
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
    locale: sway.ILocale,
    user: sway.IUser,
    bill: sway.IBill,
): Promise<boolean> => {
    const doc = db.doc(getUserVoteDocumentPath(user.uid, locale, bill));
    const snap = await doc.get();
    return isUserVoted(snap);
};

const isUserVoted = (snap: DocumentSnapshot): boolean => {
    return Boolean(snap && snap.exists);
};

const getUserVoteDocumentPath = (
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
