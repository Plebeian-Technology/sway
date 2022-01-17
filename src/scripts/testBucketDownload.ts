import { bucket } from "src/scripts/firebase";

export const downloadLocale = () => {
    bucket
        .file("geojsons/baltimore-maryland-united_states.geojson")
        .download({
            destination: "/tmp/baltimore-maryland-united_states.geojson",
        })
        .then(console.log)
        .catch(console.error);
};

downloadLocale();
