// @lat: [[sway-google-cloud-storage-design#Why the frontend bucket name is a build-time Vite variable, not a constant]]
const bucket = (import.meta.env.VITE_SWAY_ASSETS_BUCKET as string | undefined) ?? "";

export const SWAY_ASSETS_BUCKET_BASE_URL = bucket ? `https://storage.googleapis.com/${bucket}` : "";
