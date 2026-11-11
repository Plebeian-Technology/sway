export const SWAY_STORAGE = {
    Local: {
        User: {
            InvitedBy: "@sway/local/user/InvitedBy",
            Registered: "@sway/local/user/Registered",
            Phone: "@sway/user/phone",
        },
        BillCreator: {
            Bill: "@sway/creator/bill",
            Organizations: "@sway/creator/organizations",
            LegislatorVotes: "@sway/creator/legislator_votes",
        },
        Funnel: {
            VisitorToken: "@sway/funnel/visitor_token",
            AttributionKey: "@sway/funnel/attribution_key",
        },
    },
    Session: {
        User: {
            Locale: "@sway/session/user/Locale",
        },
    },
};
