import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";

const routerPatch = vi.fn<(...args: unknown[]) => void>();
vi.mock("@inertiajs/react", () => ({
    router: {
        patch: (...args: unknown[]) => routerPatch(...args),
    },
}));

const confirmMock = vi.fn<(opts: Record<string, unknown>) => Promise<boolean>>();
vi.mock("app/frontend/components/ui/confirm-dialog", () => ({ useConfirm: () => confirmMock }));

const notify = vi.fn<(...args: unknown[]) => void>();
vi.mock("app/frontend/sway_utils", () => ({ notify: (...args: unknown[]) => notify(...args) }));

import SendingServicesPanel, {
    ISendingServiceDomainRow,
} from "app/frontend/components/admin/creator/SendingServicesPanel";

const row = (overrides: Partial<ISendingServiceDomainRow> = {}): ISendingServiceDomainRow => ({
    id: 1,
    domain: "everyactioncustom.com",
    label: "proposed",
    sender_count: 279,
    machine_sent_letter_count: 279,
    letter_count: 279,
    bill_count: 1,
    ...overrides,
});

beforeEach(() => {
    routerPatch.mockClear();
    confirmMock.mockReset();
    confirmMock.mockResolvedValue(true);
    notify.mockClear();
});

describe("SendingServicesPanel", () => {
    it("renders the standing line saying what a sending-service label does and does not mean", () => {
        render(<SendingServicesPanel billId={62} domains={[]} />);

        expect(
            screen.getByText(
                "A sending service says only that a letter was machine-sent. It never says which campaign a letter belongs to, or what it argues.",
            ),
        ).toBeInTheDocument();
    });

    it("renders the empty sentence, not a table, when there are no domains", () => {
        render(<SendingServicesPanel billId={62} domains={[]} />);

        expect(screen.getByText("No sending-service domains yet.")).toBeInTheDocument();
        expect(screen.queryByRole("table")).toBeNull();
        // Still standing above the empty state, not only above a populated table.
        expect(screen.getByText(/A sending service says only/)).toBeInTheDocument();
    });

    // B11: the caption used to say "in alphabetical order", which stopped being true the moment the
    // server started ranking by machine-sent count before the cap. The caption must describe the
    // rule the rows are actually capped and ordered by, not a stale claim about their order.
    it("names the ranking rule the list is capped and ordered by, not a stale claim about alphabetical order", () => {
        render(
            <SendingServicesPanel
                billId={62}
                domains={[row({ id: 1 }), row({ id: 2, domain: "second.example.com" })]}
                total={5}
            />,
        );

        expect(
            screen.getByText(/Showing the 2 domains with the most machine-sent letters, of 5\./),
        ).toBeInTheDocument();
        expect(screen.queryByText(/alphabetical/)).toBeNull();
    });

    it("renders rows in the order the server sent them, without re-sorting (B11 — the server ranks by machine-sent count before the cap, so the client must not reshuffle)", () => {
        render(
            <SendingServicesPanel
                billId={62}
                domains={[
                    // Deliberately NOT in machine-sent order: if the panel ever resurrects client-side
                    // sorting, this order would flip and the assertion below would catch it.
                    row({ id: 1, domain: "zzz.com", machine_sent_letter_count: 5, letter_count: 10 }), // 50%
                    row({ id: 2, domain: "everyactioncustom.com", machine_sent_letter_count: 279, letter_count: 279 }), // 100%
                    row({ id: 3, domain: "aaa.com", machine_sent_letter_count: 5, letter_count: 10 }), // 50%
                ]}
            />,
        );

        // Keyed by id, never by the domain string: the domain is attacker-supplied text and a
        // test id is one of the places this phase's own rule says it must never reach.
        const rows = screen.getAllByTestId(/^sending-service-row-/);
        expect(rows.map((r) => r.getAttribute("data-testid"))).toEqual([
            "sending-service-row-1",
            "sending-service-row-2",
            "sending-service-row-3",
        ]);
    });

    it("shows a hundred-percent share built from one letter with its own bill count of one beside it", () => {
        render(
            <SendingServicesPanel
                billId={62}
                domains={[
                    row({
                        id: 9,
                        domain: "formresponse.com",
                        machine_sent_letter_count: 1,
                        letter_count: 1,
                        bill_count: 1,
                    }),
                ]}
            />,
        );

        expect(screen.getByText("100%")).toBeInTheDocument();
        expect(screen.getByText("1 of 1 letter")).toBeInTheDocument();
        expect(screen.getByRole("row", { name: /formresponse\.com/ })).toHaveTextContent("1");
    });

    it("never renders a share without its two counts", () => {
        render(<SendingServicesPanel billId={62} domains={[row()]} />);

        expect(screen.getByText("100%")).toBeInTheDocument();
        expect(screen.getByText("279 of 279 letters")).toBeInTheDocument();
    });

    // WR-06. The table carries three labels and the default is "none". Nothing in this codebase
    // ever writes "proposed" — the whole design is that no threshold proposes a domain — so
    // stamping every unlabeled domain PROPOSED said a threshold had spoken when none had.
    it("shows one stamp per label, and never calls an unlabeled domain proposed", () => {
        render(
            <SendingServicesPanel
                billId={62}
                domains={[
                    row({ id: 1, domain: "confirmed.example.com", label: "confirmed" }),
                    row({ id: 2, domain: "unlabeled.example.com", label: "none" }),
                    row({ id: 3, domain: "proposed.example.com", label: "proposed" }),
                ]}
            />,
        );

        expect(screen.getByTestId("sending-service-stamp-1")).toHaveTextContent("CONFIRMED");
        expect(screen.getByTestId("sending-service-stamp-2")).toHaveTextContent("UNLABELED");
        expect(screen.getByTestId("sending-service-stamp-3")).toHaveTextContent("PROPOSED");
    });

    it("opens the confirm dialog with the exact title, description and button labels, then PATCHes on confirm", async () => {
        render(<SendingServicesPanel billId={62} domains={[row({ label: "none" })]} />);

        fireEvent.click(screen.getByTestId("btn-confirm-sending-service-1"));

        await waitFor(() => expect(confirmMock).toHaveBeenCalledTimes(1));
        expect(confirmMock).toHaveBeenCalledWith({
            title: "Confirm everyactioncustom.com as a sending service?",
            description:
                "Every future letter from this domain will be marked machine-sent. This does not say what those letters argue.",
            confirmLabel: "Confirm",
            cancelLabel: "Cancel",
        });

        await waitFor(() =>
            expect(routerPatch).toHaveBeenCalledWith(
                "/sending_service_domains/1",
                { label: "confirmed", bill_id: 62 },
                expect.objectContaining({ preserveScroll: true }),
            ),
        );
    });

    it("opens the removal dialog with the exact title, description and button labels, then PATCHes on confirm", async () => {
        render(<SendingServicesPanel billId={62} domains={[row({ label: "confirmed" })]} />);

        fireEvent.click(screen.getByTestId("btn-remove-sending-service-1"));

        await waitFor(() => expect(confirmMock).toHaveBeenCalledTimes(1));
        expect(confirmMock).toHaveBeenCalledWith({
            title: "Remove the sending-service label from everyactioncustom.com?",
            description: "Future letters from this domain will be read as one person's letter.",
            confirmLabel: "Remove the label",
            cancelLabel: "Cancel",
        });

        await waitFor(() =>
            expect(routerPatch).toHaveBeenCalledWith(
                "/sending_service_domains/1",
                { label: "none", bill_id: 62 },
                expect.objectContaining({ preserveScroll: true }),
            ),
        );
    });

    it("does not PATCH when the confirmation is dismissed", async () => {
        confirmMock.mockResolvedValue(false);
        render(<SendingServicesPanel billId={62} domains={[row({ label: "none" })]} />);

        fireEvent.click(screen.getByTestId("btn-confirm-sending-service-1"));

        await waitFor(() => expect(confirmMock).toHaveBeenCalledTimes(1));
        expect(routerPatch).not.toHaveBeenCalled();
    });

    it("disables only the submitting row's buttons, leaving other rows usable", async () => {
        let finishPatch: (() => void) | undefined;
        routerPatch.mockImplementation((..._args: unknown[]) => {
            const opts = _args[2] as { onFinish?: () => void };
            finishPatch = () => opts.onFinish?.();
        });

        render(
            <SendingServicesPanel
                billId={62}
                domains={[
                    row({ id: 1, domain: "a.example.com", label: "none" }),
                    row({ id: 2, domain: "b.example.com", label: "none" }),
                ]}
            />,
        );

        fireEvent.click(screen.getByTestId("btn-confirm-sending-service-1"));
        await waitFor(() => expect(routerPatch).toHaveBeenCalled());

        expect(screen.getByTestId("btn-confirm-sending-service-1")).toBeDisabled();
        expect(screen.getByTestId("btn-not-sending-service-1")).toBeDisabled();
        expect(screen.getByTestId("btn-confirm-sending-service-2")).not.toBeDisabled();
        expect(screen.getByTestId("btn-not-sending-service-2")).not.toBeDisabled();

        act(() => finishPatch?.());
        await waitFor(() => expect(screen.getByTestId("btn-confirm-sending-service-1")).not.toBeDisabled());
    });

    it("shows the refusal through the sending_service channel on error, and the row is not locally re-labeled", async () => {
        routerPatch.mockImplementation((..._args: unknown[]) => {
            const opts = _args[2] as { onError?: (errors: unknown) => void };
            opts.onError?.({ sending_service: "Unknown label value" });
        });

        render(<SendingServicesPanel billId={62} domains={[row({ label: "none" })]} />);
        fireEvent.click(screen.getByTestId("btn-confirm-sending-service-1"));

        await waitFor(() => expect(notify).toHaveBeenCalledWith({ level: "error", title: "Unknown label value" }));
        // The panel reads its label straight from props — no optimistic write — so the stamp is
        // still UNLABELED, not CONFIRMED, after a refusal.
        expect(screen.getByTestId("sending-service-stamp-1")).toHaveTextContent("UNLABELED");
    });

    it("wraps a long domain rather than clamping it", () => {
        const longDomain = `${"a".repeat(200)}.example.com`;
        render(<SendingServicesPanel billId={62} domains={[row({ domain: longDomain })]} />);

        const cell = screen.getByText(longDomain);
        expect(cell.className).not.toMatch(/line-clamp/);
        expect(cell.className).toMatch(/break-all/);
    });

    it("never selects the destructive variant or tone on any control the panel owns", () => {
        render(
            <SendingServicesPanel
                billId={62}
                domains={[row({ label: "confirmed" }), row({ id: 2, domain: "other.com" })]}
            />,
        );

        for (const el of document.querySelectorAll("[data-variant], [data-tone]")) {
            expect(el.getAttribute("data-variant")).not.toBe("destructive");
            expect(el.getAttribute("data-tone")).not.toBe("danger");
        }
    });

    it("shows at most five domains per page using the shared paginator, and the total-count line keeps reporting the true server total", () => {
        const many = Array.from({ length: 7 }, (_, i) => row({ id: i + 1, domain: `domain-${i + 1}.example.com` }));
        render(<SendingServicesPanel billId={62} domains={many} total={40} />);

        expect(screen.getAllByTestId(/^sending-service-row-/)).toHaveLength(5);
        expect(
            screen.getByText(/Showing the 7 domains with the most machine-sent letters, of 40\./),
        ).toBeInTheDocument();

        fireEvent.click(screen.getByRole("button", { name: "Page 2" }));

        expect(screen.getAllByTestId(/^sending-service-row-/)).toHaveLength(2);
        expect(
            screen.getByText(/Showing the 7 domains with the most machine-sent letters, of 40\./),
        ).toBeInTheDocument();
    });

    it("filters rows by domain as the operator types, paging the filtered set without stranding the operator on a page a shrinking search emptied", () => {
        const many = Array.from({ length: 7 }, (_, i) => row({ id: i + 1, domain: `domain-${i + 1}.example.com` }));
        render(<SendingServicesPanel billId={62} domains={many} total={40} />);

        fireEvent.click(screen.getByRole("button", { name: "Page 2" }));
        expect(screen.getAllByTestId(/^sending-service-row-/)).toHaveLength(2);

        fireEvent.change(screen.getByTestId("sending-services-search"), { target: { value: "domain-3" } });

        const rows = screen.getAllByTestId(/^sending-service-row-/);
        expect(rows).toHaveLength(1);
        expect(rows[0]).toHaveTextContent("domain-3.example.com");
        expect(
            screen.getByText(/Showing the 7 domains with the most machine-sent letters, of 40\./),
        ).toBeInTheDocument();
    });

    it("shows a message, not an empty table, when the search matches no domain", () => {
        render(
            <SendingServicesPanel
                billId={62}
                domains={[row({ id: 1, domain: "a.example.com" }), row({ id: 2, domain: "b.example.com" })]}
            />,
        );

        fireEvent.change(screen.getByTestId("sending-services-search"), { target: { value: "zzz-no-match" } });

        expect(screen.getByText("No domains match this search.")).toBeInTheDocument();
        expect(screen.queryByRole("table")).toBeNull();
    });

    // @lat: [[pagination#A search that cannot reach every row says so]]
    it("says how many rows the search could not reach when the server capped the list", () => {
        render(
            <SendingServicesPanel
                billId={62}
                domains={[row({ id: 1, domain: "a.example.com" }), row({ id: 2, domain: "b.example.com" })]}
                total={40}
            />,
        );

        fireEvent.change(screen.getByTestId("sending-services-search"), { target: { value: "zzz-no-match" } });

        expect(
            screen.getByText(/No domains match this search among the 2 shown — 38 more are not loaded\./),
        ).toBeInTheDocument();
    });
});
