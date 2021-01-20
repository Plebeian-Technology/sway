export default {
    united_states: {
        congress: {
            congress: [
                {
                    name: "American Civil Liberties Union",
                    iconPath: "aclu.png",
                    positions: {},
                },
                {
                    name: "Democratic Party",
                    iconPath: "democrats.svg",
                    positions: {
                        "H.Res.24-117": {
                            support: true,
                            billFirestoreId: "H.Res.24-117",
                            summary: "",
                        },
                    },
                },
                {
                    name: "Republican Party",
                    iconPath: "republicans.svg",
                    positions: {
                        "H.Res.24-117": {
                            support: false,
                            billFirestoreId: "H.Res.24-117",
                            summary: "",
                        },
                    },
                },
                {
                    name: "Green Party",
                    iconPath: "green-party.jpg",
                    positions: {},
                },
                {
                    name: "Libertarian Party",
                    iconPath: "libertarian-party.jpg",
                    positions: {},
                },
            ],
        },
    },
};
