import {
    Collections,
    CONGRESS_LOCALE_NAME,
    NOTIFICATION_FREQUENCY,
    NOTIFICATION_TYPE,
} from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { isEmptyObject, titleize } from "@sway/utils";
import { DocumentSnapshot } from "firebase-admin/firestore";
import * as functions from "firebase-functions";

import { fire, sway } from "sway";
import * as Twilio from "twilio";
import { MessageInstance } from "twilio/lib/rest/api/v2010/account/message";
import { db } from "../firebase";
import { IFunctionsConfig } from "../utils";

const { logger } = functions;

export /**
 * Send an SMS/Text Message to a User if it has been EXACTLY 3 days since the last BOTW
 * was released for the locale
 *
 * @param {SwayFireClient} fireClient
 * @param {sway.IBill} bill
 * @return {*}  {boolean}
 */
const sendSMSNotification = async (
    fireClient: SwayFireClient,
    locale: sway.ILocale,
    bill: sway.IBill,
    sentSMS: string[],
    config: IFunctionsConfig,
): Promise<string[]> => {
    if (locale.name === CONGRESS_LOCALE_NAME) {
        logger.error("sendSMSNotification - locale is CONGRESS. Skipping sms send.");
        return sentSMS;
    }

    logger.info("sendSMSNotification - check if botw was created === 3 days ago");
    const isCreatedThreeDaysAgo = await getIsCreatedThreeDaysAgo(fireClient, bill.firestoreId);
    if (!isCreatedThreeDaysAgo) {
        logger.info(
            "botw was NOT created three days ago, skipping SMS send for locale -",
            locale.name,
        );
        return sentSMS;
    }

    logger.info(
        "botw notification gathering users to notify for SMS notification for locale -",
        locale.name,
    );
    const users = await getUsersToNotifyBySettings(fireClient, [
        NOTIFICATION_TYPE.Sms,
        NOTIFICATION_TYPE.EmailSms,
    ]);

    if (isEmptyObject(users)) {
        logger.error("no user phone numbers to notify for locale -", locale.name);
        return sentSMS;
    }

    logger.info(
        "botw notification filtering user phone numbers by isAlreadyVoted for locale -",
        locale.name,
    );
    const promises: Promise<string | null>[] = users.map((user: sway.IUser) =>
        filterUsersByAlreadyVoted(locale, bill, user, sentSMS),
    );

    const _phones = await Promise.all(promises);
    const phones = _phones.filter(Boolean) as string[];
    if (isEmptyObject(phones)) {
        logger.error(
            "Mapped phones from list of users is empty. All users may have voted already, or already received an email today. Skipping send for locale -",
            locale.name,
        );
        return sentSMS;
    }

    logger.info(
        "botw notification count of phones to send for locale -",
        phones.length,
        locale.name,
    );
    logger.info(
        `botw notification sending phones for locale - ${locale.name} - to -`,
        phones.filter(Boolean).map(formatTwilioToPhone),
    );

    return sendTwilioSMS(locale, phones.filter(Boolean).map(formatTwilioToPhone), config)
        .then((sentPhones: string[]) => {
            return sentPhones;
        })
        .catch((error) => {
            logger.error("Error sending twilio messages -", error);
            return phones.filter(Boolean);
        });
};

const formatTwilioToPhone = (phone: string) => {
    if (phone.startsWith("+1")) {
        return phone;
    }

    const _phone = phone.replace(/\D/g, "");
    if (_phone.length === 10) {
        return `+1${_phone}`;
    }
    if (_phone.length === 11) {
        return `+${phone}`;
    }
    throw new Error(`Invalid phone number format - ${phone}`);
};

const sendTwilioSMS = async (
    locale: sway.ILocale,
    phones: string[],
    config: IFunctionsConfig,
): Promise<string[]> => {
    logger.info("Building twilio client for locale -", locale.name);
    const client = Twilio.default(config.twilio.account_sid, config.twilio.auth_token);
    logger.info("Created twilio client for locale -", locale.name);

    const fromNumber = config.twilio.from_number;

    logger.info("Mapping and sending phones via twilio sms messages");
    const sent: Promise<string>[] = phones.map(async (phone: string): Promise<string> => {
        return await client.messages
            .create({
                body: getSMSBody(locale),
                from: fromNumber,
                to: phone,
            })
            .then((message: MessageInstance) => {
                logger.info("Twilio message sent to phone -", phone, message);
                return phone;
            })
            .catch((error) => {
                logger.error("Error sending twilio message to phone number -", phone, error);
                return phone;
            });
    });
    return await Promise.all(sent);
};

const getSMSBody = (locale: sway.ILocale): string => {
    const city = titleize(locale.city);
    return `Sway has a ${city} Bill of the Week for you to vote on!\n\rhttps://app.sway.vote/bill-of-the-week?locale=${locale.name}`;
};

const filterUsersByAlreadyVoted = async (
    locale: sway.ILocale,
    bill: sway.IBill,
    user: sway.IUser,
    sentSMS: string[],
): Promise<string | null> => {
    const localeName = locale.name;
    if (sentSMS.includes(user.phone)) {
        logger.info(
            "(map phone) user already received an SMS, skipping sending for locale -",
            localeName,
        );
        return null;
    }
    const userLocaleNames = user.locales.map((l) => l.name);
    if (!userLocaleNames.includes(localeName)) {
        logger.info(
            "(map phone) user locales does not include locale, skipping sending for locale -",
            localeName,
        );
        return null;
    }

    const isVoted = await isUserAlreadyVoted(locale, user, bill);
    if (isVoted) {
        logger.info(
            `(map phone) user - ${user.uid} - already voted on bill - ${bill.firestoreId}, skipping sending for locale -`,
            localeName,
        );
        return null;
    }
    return user.phone;
};

const getIsCreatedThreeDaysAgo = async (
    fireClient: SwayFireClient,
    billFirestoreId: string,
): Promise<boolean | void> => {
    return fireClient
        .bills()
        .get(billFirestoreId)
        .then((bill: sway.IBill | undefined) => {
            if (!bill) return false;

            const createdAt = bill.createdAt;
            if (!createdAt) return false;

            const differenceInMilliseconds = new Date().valueOf() - createdAt.valueOf();
            const differenceInDays = differenceInMilliseconds / (1000 * 60 * 60 * 24);
            const roundedDifferenceInDays = Math.round(differenceInDays);
            logger.info(
                `Time differences for BOTW in locale - ${fireClient?.locale?.name}`,
                JSON.stringify(
                    {
                        differenceInMilliseconds,
                        differenceInDays,
                        roundedDifferenceInDays,
                    },
                    null,
                    4,
                ),
            );
            return roundedDifferenceInDays === 3;
        })
        .catch(logger.error);
};

const getUsersToNotifyBySettings = async (
    fireClient: SwayFireClient,
    notificationTypes: number[],
): Promise<sway.IUser[]> => {
    const settingsSnap = (await fireClient
        .userSettings("taco")
        .where("notificationFrequency", "!=", NOTIFICATION_FREQUENCY.Off)
        .where("notificationType", "in", notificationTypes)
        .get()) as fire.TypedQuerySnapshot<sway.IUserSettings>;

    if (!settingsSnap) {
        logger.error(
            "no user settings found to send notification to for locale -",
            fireClient.locale?.name,
        );
        return [];
    }

    const settingsUids = settingsSnap.docs.map(
        (setting: fire.TypedQueryDocumentSnapshot<sway.IUserSettings>) => setting.data().uid,
    );

    const users = await getUsers(fireClient, settingsUids);
    if (!users) return [];

    return users;
};

const getUsers = async (fireClient: SwayFireClient, uids: string[]): Promise<sway.IUser[]> => {
    const locale = fireClient.locale;
    if (!locale) {
        logger.error("fireClient has no locale when getting users for SMS botw notification");
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
    locale: sway.ILocale,
    user: sway.IUser,
    bill: sway.IBill,
): Promise<boolean> => {
    const doc = db.doc(userVoteDocumentPath(user.uid, locale, bill));
    const snap = await doc.get();
    return isUserVoted(snap);
};

const isUserVoted = (snap: DocumentSnapshot): boolean => {
    return Boolean(snap && snap.exists);
};

const userVoteDocumentPath = (uid: string, locale: sway.ILocale, bill: sway.IBill) => {
    logger.info(
        "Checking for user vote at path -",
        `${Collections.UserVotes}/${locale.name}/${uid}/${bill.firestoreId}`,
    );
    return `${Collections.UserVotes}/${locale.name}/${uid}/${bill.firestoreId}`;
};
