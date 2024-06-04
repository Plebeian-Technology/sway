import { logDev } from "app/frontend/sway_utils";
import { isPlainObject } from "lodash";
import { sway } from "sway";

export const isHTTP = (str: any) => typeof str === "string" && str.startsWith("http");

export const isBlobString = (str: any) => typeof str === "string" && str.startsWith("blob:http");

export const isFailedRequest = (result: unknown): boolean => {
    return !!(
        result &&
        isPlainObject(result) &&
        "success" in (result as sway.IValidationResult) &&
        !(result as sway.IValidationResult).success
    );
};

export const sendXHRRequest = async (
    resolve: (value: boolean) => void,
    file: File,
    bucketFilePath: string,
    signedURL: string,
    options: sway.files.IXHRFileUploadRequestOptions = {},
) => {
    if (options.onProgress) {
        options.onProgress(bucketFilePath, file.name, 0.01);
    }

    // https://stackoverflow.com/a/40311906/6410635
    const xhr = new XMLHttpRequest();
    xhr.open("PUT", signedURL, true);

    // Progress event listener - https://stackoverflow.com/a/60239011/6410635
    xhr.upload.addEventListener("progress", (e) => {
        if (e.lengthComputable && options.onProgress) {
            options.onProgress(bucketFilePath, file.name, Math.ceil((e.loaded / e.total) * 100.0));
        }
    });

    xhr.onabort = () => {
        console.error("sendXHRRequest - XHR file upload request aborted.");
        resolve(false);
    };

    xhr.onloadend = () => {
        logDev("sendXHRRequest - XHR file onloadend event");
        options?.onDone?.({ bucketFilePath, url: "" } as sway.files.IFileUpload, 100);
    };

    xhr.onload = () => {
        // const x = {
        //     ...xhr,
        //     status: Math.floor(Math.random() * 11) < 2 ? 200 : 503,
        //     statusText: "Slow Down",
        // };

        if (xhr.status === 503 && xhr.statusText === "Slow Down") {
            if (options.retryCount && options.retryCount >= 10) {
                console.error(
                    `sendXHRRequest - XHR request.onload status !== 200. Status: ${xhr.status}: ${xhr.statusText}`,
                );
                resolve(false);
            } else {
                return window.setTimeout(
                    () => {
                        return sendXHRRequest(resolve, file, bucketFilePath, signedURL, {
                            ...options,
                            retryCount: options.retryCount ? options.retryCount + 1 : 1,
                        });
                    },
                    Math.floor(Math.random() * 100) + 100,
                );
            }
        } else if (new RegExp(/^2/).exec(xhr.status.toString())) {
            resolve(true);
        } else if (options.retryCount && options.retryCount < 2) {
            return window.setTimeout(
                () => {
                    return sendXHRRequest(resolve, file, bucketFilePath, signedURL, {
                        ...options,
                        retryCount: options.retryCount ? options.retryCount + 1 : 1,
                    });
                },
                Math.floor(Math.random() * 100) + 100,
            );
        } else {
            console.error(
                `sendXHRRequest - XHR request.onload status !== 200. Status: ${xhr.status}: ${xhr.statusText}. Retry count - ${options.retryCount}`,
            );
            resolve(false);
        }
    };

    xhr.onerror = () => {
        console.error(`sendXHRRequest - Error in XHR request uploading file. Status: ${xhr.status}: ${xhr.statusText}`);
        // deleteFileUpload(bucketFilePath).catch(console.error);
        resolve(false);
    };

    xhr.send(file);
};
