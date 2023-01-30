import { readdirSync, statSync } from "fs";
import { resolve } from "path";
import { bucket } from "./firebase";

const UNSUPPORTED_FILES = [".DS_Store"];

// * NOTE: runtime __dirname is sway/packages/seeds/dist/src
const ASSETS_DIRECTORY = resolve(`${__dirname}/../../assets`);

// https://firebase.google.com/docs/storage/web/upload-files
const seed = () => {
    readDirectory(ASSETS_DIRECTORY);
};

const readDirectory = (path: string) => {
    const subs = readdirSync(path);
    subs.forEach(async (sub) => {
        const fullpath = `${path}/${sub}`;

        const stat = statSync(fullpath);
        if (stat.isDirectory()) {
            readDirectory(resolve(fullpath));
        } else if (stat.isFile()) {
            await upload(resolve(fullpath), resolve(fullpath.replace(`${ASSETS_DIRECTORY}/`, "")));
        }
    });
};

const isNotSupported = (filename: string) => {
    return filename.startsWith(".") || UNSUPPORTED_FILES.some((f) => filename.includes(f));
};

const upload = async (path: string, destination: string): Promise<boolean | void> => {
    console.log(`seeds.storage.upload - verify ${destination} does not exist before uploading`);
    const [exists] = await bucket.file(destination).exists();
    if (exists) {
        // console.log(
        //     `File - ${destination} - already exists in bucket. Skipping upload.`,
        // );
        if (isNotSupported(destination)) {
            console.log(
                `seeds.storage.upload - existing file at bucket path - ${destination} - IS NOT SUPPORTED. Deleting from storage.`,
                destination,
            );
            await bucket.file(destination).delete().catch(console.error);
        }
        console.log(
            `seeds.storage.upload - existing file found at bucket path - ${destination}`,
            destination,
        );
        return;
    }
    if (isNotSupported(destination)) {
        console.log(
            `seeds.storage.upload - bucket path - ${destination} - is NOT A SUPPORTED FILE. Skipping upload.`,
        );
        return;
    }

    console.log(
        `seeds.storage.upload - uploading local path - ${path} - to bucket path - ${destination}`,
    );
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
