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
        uid: string
    ) {
        super(firestore, locale, firestoreConstructor);
        this.uid = uid;
    }

    private collection = (): fire.TypedCollectionReference<sway.IUserInvites> => {
        return this.firestore.collection(
            Collections.UserInvites
        ) as fire.TypedCollectionReference<sway.IUserInvites>;
    };

    private ref = (): fire.TypedDocumentReference<sway.IUserInvites> | undefined => {
        return this.collection().doc(this.uid);
    };

    private snapshot = async (): Promise<fire.TypedDocumentSnapshot<sway.IUserInvites> | undefined> => {
        const ref = this.ref();
        if (!ref) return;

        return ref.get();
    };

    public get = async (): Promise<sway.IUserInvites | undefined> => {
        const snap = await this.snapshot();
        if (!snap) return;

        return snap.data() as sway.IUserInvites;
    };

    public create = async (
        uid: string
    ): Promise<sway.IUserInvites | undefined> => {
        const ref = this.ref();
        if (!ref) return;

        const emails = [uid];

        await ref
            .set({
                emails: this.firestoreConstructor.FieldValue.arrayUnion(uid),
            })
            .catch(console.error);
        return { emails };
    };

    public upsert = async (
        uid: string
    ): Promise<sway.IUserInvites | undefined> => {
        const snap = await this.snapshot();
        if (!snap || !snap.exists) {
            return this.create(uid);
        }

        const current: sway.IUserInvites = (snap.data() ||
            []) as sway.IUserInvites;

        const emails = current.emails.concat(uid);

        await snap.ref.update({
            emails: this.firestoreConstructor.FieldValue.arrayUnion(uid),
        });

        return { emails };
    };
}

export default FireUserInvites;
