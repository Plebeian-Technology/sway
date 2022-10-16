/** @format */

import { Collections } from "@sway/constants";
import { logDev } from "@sway/utils/index";
import { FieldValue } from "firebase/firestore";
import { fire, sway } from "sway";
import AbstractFireSway from "./abstract_legis_firebase";

class FireBillScores extends AbstractFireSway {
    private collection = (): fire.TypedCollectionReference<sway.IBillScore> => {
        return this.firestore
            .collection(Collections.BillScores)
            .doc(this?.locale?.name)
            .collection(Collections.BillScores) as fire.TypedCollectionReference<sway.IBillScore>;
    };

    private ref = (billFirestoreId: string): fire.TypedDocumentReference<sway.IBillScore> => {
        return this.collection().doc(billFirestoreId);
    };

    public snapshot = async (
        billFirestoreId: string,
    ): Promise<fire.TypedDocumentSnapshot<sway.IBillScore> | void> => {
        return this.ref(billFirestoreId).get().catch(this.logError);
    };

    public get = async (billFirestoreId: string): Promise<sway.IBillScore | undefined> => {
        const snap = await this.snapshot(billFirestoreId);
        if (!snap) return;

        return snap.data();
    };

    public create = async (
        billFirestoreId: string,
        { districts }: { districts: Record<string, any> },
    ) => {
        const now = new Date();
        const inc = this.firestoreConstructor?.FieldValue?.increment;
        const _data: sway.IBillScore = {
            createdAt: now,
            updatedAt: now,
            districts: districts,
            for: inc ? inc(0) : 0,
            against: inc ? inc(0) : 0,
        };
        return this.ref(billFirestoreId).set(_data).catch(this.logError);
    };

    public update = async (
        billFirestoreId: string,
        support: "for" | "against",
        district: string,
    ): Promise<sway.IBillScore | undefined> => {
        const ref = this.ref(billFirestoreId);
        if (!ref) return;

        const snap = await ref.get().catch(this.logError);
        if (!snap) return;

        const data = snap.data();
        if (!data) {
            console.warn("No data for bill score found - creating");
            this.create(billFirestoreId, { districts: { [district]: 0 } });
            return this.update(billFirestoreId, support, district);
        }

        console.dir(this?.firestoreConstructor, { depth: null });
        const inc = this?.firestoreConstructor?.FieldValue?.increment;

        await ref
            .update({
                updatedAt: new Date(),
                [support]: inc ? inc(1) : (data[support] as number) + 1,
            })
            .catch(this.logError);

        const currentDistrict = data.districts[district][support];
        await ref
            .update({
                [`districts.${district}.${support}`]: inc
                    ? inc(1)
                    : currentDistrict
                    ? typeof currentDistrict === "number"
                        ? currentDistrict + 1
                        : Number(currentDistrict) + 1
                    : 1,
            })
            .catch(this.logError);
        return this.get(billFirestoreId);
    };
}

export default FireBillScores;
