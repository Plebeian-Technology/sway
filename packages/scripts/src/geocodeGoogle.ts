// @ts-ignore
const fetch = (...args) => import("node-fetch").then(({ default: fetch }) => fetch(...args)); // eslint-disable-line

const geocodeGoogle = () => {
    const BASE_GOOGLE_URL = "https://maps.googleapis.com/maps/api/geocode/json";
    const address = "645 W END AVE APT 8D";
    const apikey = "";

    const url = `${BASE_GOOGLE_URL}?address=${address}&key=${apikey}`;
    fetch(url)
        .then((response) => {
            console.log({ response });
            return response.json() as Record<string, any>;
        })
        .then((json: Record<string, any>) => {
            console.dir({ json }, { depth: null });
        })
        .catch(console.error);
};

// geocodeGoogle();

export default geocodeGoogle;
