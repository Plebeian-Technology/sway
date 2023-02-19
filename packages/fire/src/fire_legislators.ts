/** @format */

import { Collections } from "@sway/constants";
import { fire, sway } from "sway";
import AbstractFireSway from "./abstract_legis_firebase";
import { Legislator as LegislatorClass } from "./classes";

class FireLegislators extends AbstractFireSway {
    public collection = (): fire.TypedCollectionReference<sway.IBasicLegislator> => {
        return this.firestore
            .collection(Collections.Legislators)
            .doc(this?.locale?.name)
            .collection(
                Collections.Legislators,
            ) as fire.TypedCollectionReference<sway.IBasicLegislator>;
    };

    public ref = (
        externalLegislatorId: string,
    ): fire.TypedDocumentReference<sway.IBasicLegislator> => {
        return this.collection().doc(externalLegislatorId);
    };

    private snapshot = (
        externalLegislatorId: string,
    ): Promise<fire.TypedDocumentSnapshot<sway.IBasicLegislator>> => {
        return this.ref(externalLegislatorId).get();
    };

    public representatives = async (
        district: string,
        regionCode: string,
        isActive = true,
    ): Promise<sway.ILegislator[]> => {
        const code = regionCode.toUpperCase();
        // console.log("fire_legislators.representatives", {
        //     code,
        //     district,
        //     isActive,
        //     locale: this.locale?.name,
        // });
        const snap = await this.collection()
            .where("regionCode", "==", code) // @ts-ignore
            .where("district", "in", [
                `${code}0`,
                0,
                "0",
                district,
                Number(district),
                `${code}${district}`,
            ])
            .where("active", "==", isActive)
            .get();

        if (!snap) return [];

        return snap.docs.map((l) => {
            return LegislatorClass.create(l.data()) as sway.ILegislator;
        });
    };

    public where = (key: "active", operator: any, value: any): fire.TypedQuery<any> => {
        return this.collection().where(key, operator, value) as fire.TypedQuery<any>;
    };

    public list = async (): Promise<(sway.ILegislator | undefined)[] | undefined> => {
        const snap: fire.TypedQuerySnapshot<sway.IBasicLegislator> = await this.collection()
            .where("active", "==", true)
            .orderBy("district", "desc")
            .limit(1000)
            .get();
        if (!snap) return;

        const legislatorSnapshots: fire.TypedQueryDocumentSnapshot<sway.IBasicLegislator>[] =
            snap.docs;

        return Promise.all(
            legislatorSnapshots
                .map((lsnap: fire.TypedQueryDocumentSnapshot<sway.IBasicLegislator>) => {
                    const data = lsnap.data();
                    if (!data) return;

                    return LegislatorClass.create(data) as sway.ILegislator;
                })
                .filter(Boolean),
        );
    };

    public get = async (
        externalLegislatorId: string | undefined,
    ): Promise<sway.ILegislator | undefined> => {
        if (!externalLegislatorId) return;

        const snap = await this.snapshot(externalLegislatorId);
        if (!snap || !snap.exists) return;

        const data: sway.IBasicLegislator | undefined = snap.data();
        if (!data) return;

        return LegislatorClass.create(data) as sway.ILegislator;
    };
}

export default FireLegislators;
