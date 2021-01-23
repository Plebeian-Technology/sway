/** @format */

import { Collections, USER_LEGISLATOR as UL } from "@sway/constants";
import { sway, fire } from "sway";
import { didUserAndLegislatorAgree } from "./utils";
import AbstractFireSway from "./abstract_legis_firebase";

class FireUserLegislatorScores extends AbstractFireSway {
    private collection = (
        externalLegislatorId: string
    ): fire.TypedCollectionReference<sway.IUserLegislatorScore> => {
        return this.firestore
            .collection(Collections.UserLegislatorScores)
            .doc(this?.locale?.name)
            .collection(externalLegislatorId) as fire.TypedCollectionReference<
            sway.IUserLegislatorScore
        >;
    };

    private ref = (
        externalLegislatorId: string,
        uid: string
    ): fire.TypedDocumentReference<sway.IUserLegislatorScore> => {
        return this.collection(externalLegislatorId).doc(uid);
    };

    private snapshot = (
        externalLegislatorId: string,
        uid: string
    ): Promise<
        fire.TypedDocumentSnapshot<sway.IUserLegislatorScore>
    > | undefined => {
        return this.ref(externalLegislatorId, uid).get();
    };

    public list = async (
        externalLegislatorId: string
    ): Promise<fire.TypedQuerySnapshot<sway.IUserLegislatorScore>> => {
        return this.collection(externalLegislatorId).get();
    };

    public get = async (
        externalLegislatorId: string,
        uid: string
    ): Promise<sway.IUserLegislatorScore | undefined> => {
        const snap = await this.snapshot(externalLegislatorId, uid);
        if (!snap) return;

        return snap.data() as sway.IUserLegislatorScore;
    };

    public listen = (
        externalLegislatorId: string,
        uid: string,
        callback: (
            snapshot: fire.TypedDocumentSnapshot<sway.IUserLegislatorScore>
        ) => Promise<void>,
        errorCallback?: (params?: any) => void
    ) => {
        const ref = this.ref(externalLegislatorId, uid);
        if (!ref) return;

        return ref.onSnapshot({
            next: callback,
            error: errorCallback,
        });
    };

    public create = () => {
        return "created in cloud func";
    };

    public update = async (
        legislator: sway.ILegislator,
        legislatorVote: sway.ILegislatorVote | undefined,
        userVote: sway.IUserVote,
        userLegislatorVoteRefPath: string,
        uid: string
    ): Promise<boolean | undefined> => {
        if (!userVote.support) return;

        const legislatorId = legislator.externalId;
        const inc = this.firestoreConstructor.FieldValue.increment;

        const agreement: number | null = didUserAndLegislatorAgree(
            userVote.support,
            legislatorVote
        );

        const ref = this.ref(legislatorId, uid);
        const snap = await ref.get();

        const _field = ():
            | "totalUserLegislatorAbstained"
            | "totalUserLegislatorAgreed"
            | "totalUserLegislatorDisagreed"
            | "totalUnmatchedLegislatorVote" => {
            if (agreement === UL.MutuallyAbstained) {
                return "totalUserLegislatorAbstained";
            }
            if (agreement === UL.Agreed) {
                return "totalUserLegislatorAgreed";
            }
            if (agreement === UL.Disagreed) {
                return "totalUserLegislatorDisagreed";
            }
            return "totalUnmatchedLegislatorVote";
        };

        const field = _field();

        if (snap && snap.exists) {
            await ref.update({
                externalLegislatorId: legislatorId,
                totalUserVotes: inc(1),
                [field]: inc(1),
                userLegislatorVotes: this.firestoreConstructor.FieldValue.arrayUnion(
                    userLegislatorVoteRefPath
                ),
            });
        } else {
            await ref.set({
                externalLegislatorId: legislatorId,
                totalUserVotes: inc(1),
                totalUnmatchedLegislatorVote:
                    agreement === UL.NoLegislatorVote ? inc(1) : 0,
                totalUserLegislatorAbstained:
                    agreement === UL.MutuallyAbstained ? inc(1) : 0,
                totalUserLegislatorAgreed: agreement === UL.Agreed ? inc(1) : 0,
                totalUserLegislatorDisagreed:
                    agreement === UL.Disagreed ? inc(1) : 0,
                userLegislatorVotes: [userLegislatorVoteRefPath],
            });
        }
        return;
    };
}

export default FireUserLegislatorScores;
