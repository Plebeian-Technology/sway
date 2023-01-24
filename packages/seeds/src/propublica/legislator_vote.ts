import { Support } from "@sway/constants";
export default class PropublicaLegislatorVote {
    vote: propublica.ILegislatorVote;
    constructor(vote: propublica.ILegislatorVote) {
        this.vote = vote;
    }

    public toSwaySupport = (billExternalId: string) => {
        const position = this.vote.vote_position.toLowerCase();

        if (position === "yea") return Support.For;
        if (position === "yes") return Support.For;

        if (position === "nay") return Support.Against;
        if (position === "no") return Support.Against;

        if (position === "not voting") return Support.Abstain;
        if (position === "abstain") return Support.Abstain;
        if (position === "did not vote") return Support.Abstain;
        if (position === "present") return Support.Abstain;

        // * By tradition, the Speaker of the House rarely votes.
        // * When the Speaker does not vote, the original data provided the Clerk of the House contains no record for the Speaker on that vote.
        // * In those cases, the API records the Speaker’s voting position as Speaker, and it is not included in the vote total calculations.
        if (position === "speaker") return Support.Abstain;

        if (billExternalId.startsWith("speaker") && billExternalId.split("-").last() === "118") {
            if (position === "mccarthy") return Support.For;
            if (position === "jeffries") return Support.Against;
        }

        throw new Error(
            `PropublicaLegislatorVotes.toSwaySupport received an unexpected 'position' argument - ${position}`,
        );
    };
}
