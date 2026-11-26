// @lat: [[mobile-bill-creator#Sections#The organizations section#Organization icons]]
import { File } from "expo-file-system";

import { apiClient } from "./client";
import { Routes } from "./routes";

export interface DirectUploadFile {
    uri: string;
    filename: string;
    contentType: string;
}

interface DirectUploadBlob {
    signed_id: string;
    direct_upload: { url: string; headers: Record<string, string> };
}

const base64FromHex = (hex: string) =>
    btoa(String.fromCharCode(...(hex.match(/../g) ?? []).map((pair) => Number.parseInt(pair, 16))));

export async function directUpload({ uri, filename, contentType }: DirectUploadFile): Promise<string> {
    const file = new File(uri);
    if (!file.md5) throw new Error(`Could not read ${filename}.`);

    const blob = await apiClient.post<DirectUploadBlob>(Routes.adminDirectUploads(), {
        blob: { filename, byte_size: file.size, checksum: base64FromHex(file.md5), content_type: contentType },
    });

    const response = await fetch(blob.direct_upload.url, {
        method: "PUT",
        headers: blob.direct_upload.headers,
        body: await file.bytes(),
    });
    if (!response.ok) throw new Error(`Uploading ${filename} failed (${response.status}).`);

    return blob.signed_id;
}
