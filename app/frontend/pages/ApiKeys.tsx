import { router } from "@inertiajs/react";
import { useAxiosGet, useAxiosPost } from "app/frontend/hooks/useAxios";
import { handleError, notify } from "app/frontend/sway_utils";
import copy from "copy-to-clipboard";
import { parseISO } from "date-fns";
import { Suspense, useCallback, useMemo, useState } from "react";
import { Button, FormControl, Modal, OverlayTrigger, Table, Tooltip } from "react-bootstrap";
import { FiCopy, FiSave, FiTrash2 } from "react-icons/fi";
import { sway } from "sway";

interface IProps {
    apiKeys: sway.api.IApiKey[];
}

const ApiKeys = ({ apiKeys }: IProps) => {
    const [newApiKey, setNewApiKey] = useState<sway.api.IApiKey | null>(null);
    const [newName, setNewName] = useState<string>("");

    const { post } = useAxiosPost<sway.api.IApiKey>("/api_keys");
    const { post: put } = useAxiosPost<sway.api.IApiKey>("/api_keys/0", { method: "put" });

    const getOptions = useMemo(
        () => ({
            method: "delete" as const,
            skipInitialRequest: true,
        }),
        [],
    );
    const { get: delete_ } = useAxiosGet<{ route: string }>("/api_keys/0", getOptions);

    const create = useCallback(
        (e: React.MouseEvent<HTMLButtonElement>) => {
            e.preventDefault();

            post({})
                .then((result: sway.api.IApiKey | null) => {
                    setNewApiKey(result);
                })
                .catch(handleError);
        },
        [post],
    );

    const update = useCallback(
        (e: React.MouseEvent<HTMLButtonElement>) => {
            e.preventDefault();
            const id = e.currentTarget.id.split("-").last();

            put({ api_keys_update_params: { name: newName } }, { route: `/api_keys/${id}` })
                .then((result: sway.api.IApiKey | null) => {
                    setNewApiKey(result);
                })
                .catch(handleError);
        },
        [newName, put],
    );

    const destroy = useCallback(
        (e: React.MouseEvent<HTMLButtonElement>) => {
            e.preventDefault();
            const id = e.currentTarget.id.split("-").last();

            delete_({
                route: `/api_keys/${id}`,
            })
                .then(() => {
                    router.reload();
                })
                .catch(handleError);
        },
        [delete_],
    );

    const handleCopy = useCallback(() => {
        if (!newApiKey?.token) return;

        copy(newApiKey.token, {
            message: "Click to Copy",
            format: "text/plain",
            onCopy: () =>
                notify({
                    level: "info",
                    title: "Copied API Key",
                }),
        });
        return "";
    }, [newApiKey?.token]);

    return (
        <>
            <Suspense fallback={null}>
                {newApiKey?.token && (
                    <Modal show={true}>
                        <Modal.Header>
                            <Modal.Title>New API Key</Modal.Title>
                        </Modal.Header>
                        <Modal.Body>
                            <p>Store this new API Key securely, this is the only time it will be shown.</p>
                            <p>If you require a new API Key, simply delete this one and create a new one.</p>
                            <p>You are permitted at most 1 API Key.</p>
                            <p>
                                <span className="bold">API Key:</span>
                                <Button as="span" variant="link" onClick={handleCopy} className="py-0">
                                    {newApiKey.token}&nbsp;
                                    <FiCopy />
                                </Button>
                            </p>
                        </Modal.Body>
                        <Modal.Footer>
                            <Button
                                onClick={(_e) => {
                                    setNewApiKey(null);
                                    router.reload();
                                }}
                            >
                                I saved my API Key
                            </Button>
                        </Modal.Footer>
                    </Modal>
                )}
            </Suspense>
            {!apiKeys.length && (
                <div className="row mt-5">
                    <div className="col">
                        <Button onClick={create}>Create API Key</Button>
                    </div>
                </div>
            )}
            <Table responsive hover bordered className="mt-5">
                <thead>
                    <tr>
                        <th>Name</th>
                        <th>Created At</th>
                        <th>Last Used On</th>
                        <th>{""}</th>
                    </tr>
                </thead>
                <tbody>
                    {apiKeys.map((apiKey) => {
                        return (
                            <tr key={apiKey.id}>
                                <td>
                                    {apiKey.name || (
                                        <FormControl
                                            autoFocus
                                            onChange={(e) => setNewName(e.currentTarget.value)}
                                            value={newName}
                                        />
                                    )}
                                </td>
                                <td>{parseISO(apiKey.created_at).toLocaleDateString("en-US")}</td>
                                <td>
                                    {apiKey.last_used_on_utc
                                        ? parseISO(apiKey.last_used_on_utc).toLocaleDateString("en-US")
                                        : null}
                                </td>
                                <td>
                                    <OverlayTrigger overlay={<Tooltip>Update API Key Name</Tooltip>}>
                                        <Button
                                            variant="primary"
                                            onClick={update}
                                            id={`update-${apiKey.id.toString()}`}
                                            className="me-3"
                                            disabled={!newName}
                                        >
                                            <FiSave />
                                        </Button>
                                    </OverlayTrigger>
                                    <OverlayTrigger overlay={<Tooltip>Delete API Key</Tooltip>}>
                                        <Button
                                            variant="danger"
                                            onClick={destroy}
                                            id={`delete-${apiKey.id.toString()}`}
                                        >
                                            <FiTrash2 />
                                        </Button>
                                    </OverlayTrigger>
                                </td>
                            </tr>
                        );
                    })}
                </tbody>
            </Table>
        </>
    );
};

export default ApiKeys;
