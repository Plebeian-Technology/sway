import * as fs from "fs";
import { bucket } from "./firebase";

const UNSUPPORTED_FILES = [".DS_Store"];

// * NOTE: runtime __dirname is sway/packages/seeds/dist/src
const ASSETS_DIRECTORY = `${__dirname}/../../assets`;

// https://firebase.google.com/docs/storage/web/upload-files
const seed = () => {
    readDirectory(ASSETS_DIRECTORY);
};

const readDirectory = (path: string) => {
    const subs = fs.readdirSync(path);
    subs.forEach(async (sub) => {
        const fullpath = `${path}/${sub}`;

        const stat = fs.statSync(fullpath);
        if (stat.isDirectory()) {
            readDirectory(fullpath);
        } else if (stat.isFile()) {
            await upload(
                fullpath,
                fullpath.replace(`${ASSETS_DIRECTORY}/`, ""),
            );
        }
    });
};

const upload = async (
    path: string,
    destination: string,
): Promise<boolean | void> => {
    const [exists] = await bucket.file(destination).exists();
    if (exists) {
        // console.log(
        //     `File - ${destination} - already exists in bucket. Skipping upload.`,
        // );
        if (UNSUPPORTED_FILES.some((f) => destination.includes(f))) {
            console.log(
                `File - ${destination} - DELETING from storage since it is not supported.`,
                destination,
            );
            await bucket.file(destination).delete().catch(console.error);
        }
        return;
    }
    if (UNSUPPORTED_FILES.some((f) => destination.includes(f))) {
        // console.log(`File - ${destination} - is UNSUPPORTED skipping upload`);
        return;
    }

    console.log(`File - ${destination} - UPLOADING`, destination);
    return bucket
        .upload(path, {
            destination,
            metadata: {
                // Enable long-lived HTTP caching headers
                // Use only if the contents of the file will never change
                // (If the contents will change, use cacheControl: 'no-cache')
                cacheControl: "public, max-age=31536000",
            },
        })
        .then(() => true)
        .catch(console.error);
};

export default seed;
