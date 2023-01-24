// eslint-disable-next-line
export namespace propublica {
    export interface ILegislator {
        id: {
            bioguide: string;
            thomas: string;
            lis: string;
            govtrack: number;
            opensecrets: string;
            votesmart: number;
            fec: string[];
            cspan: number;
            wikipedia: string;
            house_history: number;
            ballotpedia: string;
            maplight: number;
            icpsr: number;
            wikidata: string;
            google_entity_id: string;
        };
        name: {
            first: string;
            last: string;
            official_full: string;
        };
        bio: {
            birthday: string;
            gender: "M" | "F";
        };
        terms: {
            type: string;
            start: string;
            end: string;
            state: string;
            party: "Democrat" | "Republican";
            class: number;
            url: string;
            address: string;
            phone: string;
            fax: string;
            contact_form: string;
            office: string;
            state_rank: string;
            rss_url: string;
            district?: number;
        }[];
    }

    export interface ILegislatorSocial {
        id: {
            bioguide: string;
            thomas: string;
            govtrack: number;
        };
        social: {
            twitter: string;
            facebook: string;
            youtube: string;
            youtube_id: string;
            twitter_id: string;
            instagram: string;
        };
    }

    export interface IVote {
        congress: number;
        chamber: "House" | "Senate";
        session: 1 | 2;
        roll_call: number;
        source: string;
        url: string;
        vote_uri: string;
        bill: {
            bill_id: string;
            number: string;
            sponsor_id: string;
            api_uri: string;
            title: string;
            latest_action: string;
        };
        question: string;
        question_text: string;
        description: string;
        vote_type: string;
        date: string;
        time: string;
        result: string;
        democratic: {
            yes: number;
            no: number;
            present: number;
            not_voting: number;
            majority_position: "Yes" | "No" | "Present" | "Not Voting";
        };
        republican: {
            yes: number;
            no: number;
            present: number;
            not_voting: number;
            majority_position: "Yes" | "No" | "Present" | "Not Voting";
        };
        independent: {
            yes: number;
            no: number;
            present: number;
            not_voting: number;
        };
        total: {
            yes: number;
            no: number;
            present: number;
            not_voting: number;
        };
    }

    export interface ILegislatorVote {
        member_id: string;
        name: string;
        party: string;
        state: string;
        vote_position: "Yes" | "No" | "Present" | "Not Voting";
        dw_nominate: number;
    }

    export interface IDataFileLegislatorVote {
        [billExternalId: string]: {
            [legislatorExternalId: string]: "for" | "against" | "abstain" | null;
        };
    }
}
