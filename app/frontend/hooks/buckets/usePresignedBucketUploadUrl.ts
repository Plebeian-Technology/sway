import { useAxiosPost } from "app/frontend/hooks/useAxios";
import { sway } from "sway";

// Request a pre-signed PUT url for an upload to GCP
export const usePresignedBucketUploadUrl = () => {
    return useAxiosPost<sway.files.IFileUpload>("/buckets/assets");
};
