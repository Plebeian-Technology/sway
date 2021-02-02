const census = require("citysdk");

const lat = 39.28953
const lng = -76.58465

census(
    {
        vintage: 2019,
        geoHierarchy: {
            "tract": {
                lat,
                lng,
            },
        },
    },
    (error, censusData) => {
        if (error) throw error;
        console.dir(censusData, { depth: null })
    }
)