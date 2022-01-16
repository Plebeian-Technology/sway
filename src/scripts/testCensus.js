const census = require("citysdk");

// const lat = 39.28953;
// const lng = -76.58465;

const lat = 39.289351800000006;
const lng = -76.58483441314914;

// census(
//     {
//         vintage: 2020,
//         geoHierarchy: {
//             "tract": {
//                 lat,
//                 lng,
//             },
//         },
//     },
//     (error, censusData) => {
//         if (error) throw error;
//         console.dir(censusData, { depth: null })
//     }
// )

const caller = (error, censusData, resolve) => {
    if (error) {
        console.error(error);
        resolve(null);
    } else {
        resolve(censusData);
    }
};

const getCensusCongressional = (callback) => {
    return new Promise((resolve, reject) => {
        census(
            {
                vintage: 2020,
                geoHierarchy: {
                    "congressional district": {
                        lat,
                        lng,
                    },
                },
            },
            (error, data) => callback(error, data, resolve),
        );
    });
};

const getCensus = (callback) => {
    return new Promise((resolve, reject) => {
        census(
            {
                vintage: 2020,
                geoHierarchy: {
                    tract: {
                        lat,
                        lng,
                    },
                },
            },
            (error, data) => callback(error, data, resolve),
        );
    });
};

getCensusCongressional(caller).then((data) => {
    console.log("DATA", data);
});
