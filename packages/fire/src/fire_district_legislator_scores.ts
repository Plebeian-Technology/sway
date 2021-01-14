/** @format */

import { Collections, USER_LEGISLATOR as UL } from "@sway/constants";
import { sway, fire } from "sway";
import AbstractFireSway from "./abstract_legis_firebase";
import { didUserAndLegislatorAgree } from "./utils";

class FireLegislatorDistrictScores extends AbstractFireSway {
    private collection = (): fire.TypedCollectionReference<sway.IUserLegislatorScore> => {
        return this.firestore
            .collection(Collections.UserLegislatorScores)
            .doc(this?.locale?.name)
            .collection(
                Collections.Districts
            ) as fire.TypedCollectionReference<sway.IUserLegislatorScore>;
    };

    private documentId = (externalId: string, district: number): string => {
        return `${externalId}-${district}`;
    };

    private ref = (
        documentId: string
    ): fire.TypedDocumentReference<sway.IUserLegislatorScore> => {
        return this.collection().doc(documentId);
    };

    private snapshot = (
        documentId: string
    ): Promise<
        fire.TypedDocumentSnapshot<sway.IUserLegislatorScore>
    > | void => {
        return this.ref(documentId).get();
    };

    public get = async (
        externalId: string,
        district: number
    ): Promise<sway.IUserLegislatorScore | void> => {
        const snap = await this.snapshot(this.documentId(externalId, district));
        if (!snap) return;

        return snap.data() as sway.IUserLegislatorScore;
    };

    public create = () => {
        throw new Error(
            "fire_district_legislator_scores.create is called in fire_district_legislator_scores.update"
        );
    };

    public update = async (
        legislator: sway.ILegislator,
        legislatorVote: sway.ILegislatorVote | void,
        userVote: sway.IUserVote,
        userLegislatorVoteRefPath: string
    ) => {
        if (!userVote.support) return;

        const inc = this.firestoreConstructor.FieldValue.increment;

        const agreement: number | null = didUserAndLegislatorAgree(
            userVote.support,
            legislatorVote
        );

        const ref = this.ref(
            this.documentId(legislator.externalId, legislator.district)
        );
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

        if (snap.exists) {
            return ref
                .update({
                    externalLegislatorId: legislator.externalId,
                    totalUserVotes: inc(1),
                    [field]: inc(1),
                    userLegislatorVotes: this.firestoreConstructor.FieldValue.arrayUnion(
                        userLegislatorVoteRefPath
                    ),
                })
                .then(() => true);
        } else {
            return ref
                .set({
                    externalLegislatorId: legislator.externalId,
                    totalUserVotes: inc(1),
                    totalUnmatchedLegislatorVote:
                        agreement === UL.NoLegislatorVote ? inc(1) : 0,
                    totalUserLegislatorAbstained:
                        agreement === UL.MutuallyAbstained ? inc(1) : 0,
                    totalUserLegislatorAgreed:
                        agreement === UL.Agreed ? inc(1) : 0,
                    totalUserLegislatorDisagreed:
                        agreement === UL.Disagreed ? inc(1) : 0,
                    userLegislatorVotes: [userLegislatorVoteRefPath],
                })
                .then(() => true);
        }
    };
}

export default FireLegislatorDistrictScores;
