const census = require("citysdk");

const lat = 39.28953;
const lng = -76.58465;

// census(
//     {
//         vintage: 2019,
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

const getCensus = (callback) => {
    return new Promise((resolve, reject) => {
        census(
            {
                vintage: 2019,
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

getCensus(caller).then((data) => {
    console.log("DATA", data)
});
