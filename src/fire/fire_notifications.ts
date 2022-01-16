/** @format */

import { Collections } from "src/constants";
import { get } from "src/utils";
import { fire, sway } from "sway";
import AbstractFireSway from "./abstract_legis_firebase";

class FireNotifications extends AbstractFireSway {
    private collection = () => {
        return this.firestore.collection(Collections.Notifications);
    };

    private ref = (): fire.TypedDocumentReference<sway.INotification> => {
        if (!this.locale)
            throw new Error("FireNotifications initialized without locale");
        return this.collection().doc(this.locale.name);
    };

    private snapshot = async (): Promise<
        fire.TypedDocumentSnapshot<sway.INotification>
    > => {
        return this.ref().get();
    };

    public get = async (date: string): Promise<string | undefined> => {
        const snap = await this.snapshot();
        if (!snap) return;

        return get(snap.data(), date);
    };

    public create = async (date: string) => {
        return this.ref().set({
            date,
        });
    };
}

export default FireNotifications;
