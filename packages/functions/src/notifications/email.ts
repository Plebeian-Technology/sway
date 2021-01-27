import * as sendgrid from "@sendgrid/mail";
import {
    Collections,
    CONGRESS_LOCALE_NAME,
    NOTIFICATION_FREQUENCY,
    NOTIFICATION_TYPE,
} from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { isEmptyObject, titleize } from "@sway/utils";
import * as functions from "firebase-functions";
import { DocumentSnapshot } from "firebase-functions/lib/providers/firestore";
import { fire, sway } from "sway";
import { db } from "../firebase";

const { logger } = functions;

export const sendSendgridEmail = async (
    fireClient: SwayFireClient,
    config: sway.IPlainObject,
    emails: string[] | string,
    templateId: string,
) => {
    const { locale } = fireClient;
    if (!locale) {
        throw new Error(
            "fireClient does not include locale when sending sendgrid email",
        );
    }
    logger.info("Sending sendgrid email.");
    const localeName =
        locale.name === CONGRESS_LOCALE_NAME
            ? "Congress"
            : `${titleize(locale.city)}, ${locale.regionCode.toUpperCase()}`;

    const to =
        typeof emails === "string" ? emails : config.sendgrid.fromaddress;
    const bcc = typeof emails === "string" ? "" : emails;

    sendgrid.setApiKey(config.sendgrid.apikey);
    const msg = {
        to,
        bcc,
        from: config.sendgrid.fromaddress,
        templateId: templateId,
        dynamicTemplateData: {
            localeName,
        },
    };
    return sendgrid.send(msg).then(logger.info).catch(logger.error);
};

export const sendWelcomeEmail = (
    fireClient: SwayFireClient,
    config: sway.IPlainObject,
    email: string,
    success: boolean,
) => {
    if (!success) return;

    return sendSendgridEmail(
        fireClient,
        config,
        email,
        config.sendgrid.welcometemplateid,
    ).then(() => true);
};

export const sendBotwEmailNotification = async (
    fireClient: SwayFireClient,
    config: sway.IPlainObject,
    bill: sway.IBill,
    isNewBill: boolean,
) => {
    logger.info("botw notification preparing email notification");
    const users = await usersToNotify(fireClient, [
        NOTIFICATION_TYPE.Email,
        NOTIFICATION_TYPE.EmailSms,
    ]);

    logger.info("botw notification collecting user emails");
    const emails =
        users && !isEmptyObject(users)
            ? users.map((user: sway.IUser) => {
                  if (isNewBill) {
                      return user.email;
                  }
                  if (isUserAlreadyVoted(fireClient, user, bill)) {
                      return null;
                  }
                  return user.email;
              })
            : [config.sendgrid.fromaddress];

    logger.info("botw notification count of emails to send -", emails.length);
    sendSendgridEmail(
        fireClient,
        config,
        emails.filter(Boolean),
        config.sendgrid.billoftheweektemplateid,
    );
};

const usersToNotify = async (
    fireClient: SwayFireClient,
    notificationTypes: number[],
): Promise<sway.IUser[] | void> => {
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
    fireCliewnt: SwayFireClient,
    uids: string[],
): Promise<sway.IUser[]> => {
    const locale = fireCliewnt.locale;
    if (!locale) {
        throw new Error(
            "fireClient has no locale when getting users for email botw notification",
        );
    }
    const snaps = uids.map(async (uid: string) => {
        const user = await fireCliewnt.users(uid).getWithoutAdminSettings();
        if (!user) return null;

        if (locale.name === CONGRESS_LOCALE_NAME) {
            return user;
        }

        const userLocaleNames = user.locales.map((l) => l.name);
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
    if (!fireClient.locale) {
        throw new Error(
            "fireClient.locale is undefined in getNotVotedUserEmails",
        );
    }
    const doc = db.doc(userVoteDocumentPath(user.uid, fireClient.locale, bill));
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
