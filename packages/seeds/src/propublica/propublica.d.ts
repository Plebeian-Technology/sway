declare module propublica {
    interface ILegislator {
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

    interface ILegislatorSocial {
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

    interface ILegislatorVote {
        member_id: string;
        name: string;
        party: string;
        state: string;
        vote_position: "Yes" | "No" | "Not Voting";
        dw_nominate: number;
    }

    interface IDataFileLegislatorVote {
        [billExternalId: string]: {
            [legislatorExternalId: string]: "for" | "against" | "abstain" | null;
        };
    }
}
