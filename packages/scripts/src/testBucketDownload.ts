import { bucket } from "../firebase";

export const downloadLocale = () => {
    bucket
        .file("geojson/baltimore-maryland-united_states.geojson")
        .download({
            destination: "/tmp/baltimore-maryland-united_states.geojson",
        })
        .then(console.log)
        .catch(console.error);
};

downloadLocale();
