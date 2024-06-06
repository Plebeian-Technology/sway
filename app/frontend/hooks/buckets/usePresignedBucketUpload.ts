import { handleError } from "app/frontend/sway_utils";
import { sendXHRRequest } from "app/frontend/sway_utils/http";
import { useCallback } from "react";
import { sway } from "sway";

export const usePresignedBucketUpload = () => {
    return useCallback(
        async (
            file: File,
            bucketFilePath: string,
            signedURL: string,
            options: sway.files.IXHRFileUploadRequestOptions = {},
        ): Promise<boolean | undefined> => {
            if (!bucketFilePath || !signedURL) {
                return;
            }

            return new Promise((resolve) => {
                sendXHRRequest(resolve, file, bucketFilePath, signedURL, options).catch(handleError);
            });
        },
        [],
    );
};
