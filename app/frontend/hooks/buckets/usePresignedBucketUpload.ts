import { handleError } from "app/frontend/sway_utils";
import { sendXHRRequest } from "app/frontend/sway_utils/http";
import { useCallback } from "react";
import { sway } from "sway";

export const usePresignedBucketUpload = () => {
    return useCallback(
        async (
            file: File,
            bucket_file_path: string,
            signedURL: string,
            options: sway.files.IXHRFileUploadRequestOptions = {},
        ): Promise<boolean | undefined> => {
            if (!bucket_file_path || !signedURL) {
                return;
            }

            return new Promise((resolve) => {
                sendXHRRequest(resolve, file, bucket_file_path, signedURL, options).catch(handleError);
            });
        },
        [],
    );
};
