/** @format */

import { Collections } from "@sway/constants";
import { fire, sway } from "sway";
import AbstractFireSway from "./abstract_legis_firebase";

class FireUserInvites extends AbstractFireSway {
    uid: string;

    constructor(
        firestore: any,
        locale: sway.ILocale | null | undefined,
        firestoreConstructor: any,
        uid: string,
    ) {
        super(firestore, firestoreConstructor, locale);
        this.uid = uid;
    }

    private collection = (): fire.TypedCollectionReference<sway.IUserInvites> => {
        return this.firestore.collection(
            Collections.UserInvites,
        ) as fire.TypedCollectionReference<sway.IUserInvites>;
    };

    private ref = (): fire.TypedDocumentReference<sway.IUserInvites> | undefined => {
        return this.collection().doc(this.uid);
    };

    private snapshot = async (): Promise<
        fire.TypedDocumentSnapshot<sway.IUserInvites> | undefined
    > => {
        const ref = this.ref();
        if (!ref) return;

        return ref.get();
    };

    public get = async (): Promise<sway.IUserInvites | undefined> => {
        const snap = await this.snapshot();
        if (!snap) return;

        return snap.data();
    };

    public getNotSentTo = async (emails: string[]): Promise<string[]> => {
        try {
            const data = await this.get();
            if (!data?.sent) return emails;

            return emails.filter((email: string) => {
                return !data.sent.includes(email);
            });
        } catch (error) {
            this.logError(error);
            return []; // default invite has already been sent
        }
    };

    public create = async ({
        sentInviteToEmails,
        redeemedNewUserUid,
    }: {
        sentInviteToEmails?: string[];
        redeemedNewUserUid?: string;
    }): Promise<sway.IUserInvites | undefined> => {
        const ref = this.ref();
        if (!ref) return;

        const toCreate: { sent: string[]; redeemed: string[] } = {
            sent: sentInviteToEmails ? sentInviteToEmails : [],
            redeemed: redeemedNewUserUid ? [redeemedNewUserUid] : [],
        } as {
            sent: string[];
            redeemed: string[];
        };

        return ref
            .set(toCreate)
            .then(this.get)
            .catch(async (error) => {
                this.logError(error);
                return this.get();
            })
            .catch((e) => {
                this.logError(e);
                return undefined;
            });
    };

    public upsert = async ({
        sentInviteToEmails,
        redeemedNewUserUid,
    }: {
        sentInviteToEmails?: string[];
        redeemedNewUserUid?: string;
    }): Promise<sway.IUserInvites | undefined> => {
        const snap = await this.snapshot();
        if (!snap || !snap.exists) {
            return this.create({ sentInviteToEmails, redeemedNewUserUid });
        }

        if (!sentInviteToEmails && !redeemedNewUserUid) {
            return this.get();
        }

        const toUpdate: { sent: string[]; redeemed: string[] } = {} as {
            sent: string[];
            redeemed: string[];
        };
        if (sentInviteToEmails) {
            // @ts-ignore
            toUpdate.sent = this.firestoreConstructor.FieldValue.arrayUnion(...sentInviteToEmails);
        }
        if (redeemedNewUserUid) {
            // @ts-ignore
            toUpdate.redeemed = this.firestoreConstructor.FieldValue.arrayUnion(redeemedNewUserUid);
        }

        return snap.ref
            .update(toUpdate)
            .then(this.get)
            .catch(async (error) => {
                this.logError(error);
                return this.get();
            });
    };
}

export default FireUserInvites;
