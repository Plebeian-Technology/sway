/** @format */

import { Collections } from "@sway/constants";
import { fire, sway } from "sway";
import AbstractFireSway from "./abstract_legis_firebase";
import { Legislator as LegislatorClass } from "./classes";
import FireUserLegislatorScores from "./fire_user_legislator_scores";
import { IS_DEVELOPMENT } from "./utils";

class FireLegislators extends AbstractFireSway {
    private collection = (): fire.TypedCollectionReference<sway.IBasicLegislator> => {
        return this.firestore
            .collection(Collections.Legislators)
            .doc(this?.locale?.name)
            .collection(
                Collections.Legislators,
            ) as fire.TypedCollectionReference<sway.IBasicLegislator>;
    };

    private ref = (
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
        uid: string,
        district: number,
        isActive = true,
    ): Promise<(sway.ILegislatorWithUserScore | undefined)[]> => {
        const snap = await this.collection() // @ts-ignore
            .where("district", "in", [0, district])
            .where("active", "==", isActive)
            .get();
        if (!snap) return [];

        const legislators: fire.TypedQueryDocumentSnapshot<sway.IBasicLegislator>[] = snap.docs as fire.TypedQueryDocumentSnapshot<sway.IBasicLegislator>[];

        const scorer = new FireUserLegislatorScores(
            this.firestore,
            this?.locale,
            this.firestoreConstructor,
        );

        return Promise.all(
            legislators.map(
                async (
                    lsnap: fire.TypedQueryDocumentSnapshot<sway.IBasicLegislator>,
                ): Promise<sway.ILegislatorWithUserScore | undefined> => {
                    if (!lsnap) {
                        console.warn("lsnap in representatives is undefined");
                        return;
                    }
                    const data: sway.IBasicLegislator = lsnap.data();
                    if (!data) return;

                    const score =
                        uid && (await scorer.get(data.externalId, uid));

                    return {
                        legislator: LegislatorClass.create(
                            data,
                        ) as sway.ILegislator,
                        score,
                    } as sway.ILegislatorWithUserScore;
                },
            ),
        );
    };

    public list = async (): Promise<
        (sway.ILegislator | undefined)[] | undefined
    > => {
        const snap: fire.TypedQuerySnapshot<sway.IBasicLegislator> = await this.collection()
            .where("active", "==", true)
            .orderBy("district", "desc")
            .limit(IS_DEVELOPMENT ? 20 : 1000)
            .get();
        if (!snap) return;

        const legislatorSnapshots: fire.TypedQueryDocumentSnapshot<sway.IBasicLegislator>[] =
            snap.docs;

        return Promise.all(
            legislatorSnapshots
                .map(
                    (
                        lsnap: fire.TypedQueryDocumentSnapshot<sway.IBasicLegislator>,
                    ) => {
                        // @ts-ignore
                        const data: sway.IBasicLegislator = lsnap.data();
                        if (!data) return;

                        return LegislatorClass.create(
                            data,
                        ) as sway.ILegislator;
                    },
                )
                .filter(Boolean),
        );
    };

    public get = async (
        externalLegislatorId: string,
    ): Promise<sway.ILegislator | void> => {
        const snap = await this.snapshot(externalLegislatorId);
        if (!snap) return;

        const data: sway.IBasicLegislator | undefined = snap.data();
        if (!data) return;

        return LegislatorClass.create(data) as sway.ILegislator;
    };
}

export default FireLegislators;
