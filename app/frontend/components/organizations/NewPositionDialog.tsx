// @lat: [[new-position-dialog-design#Why shadcn Select instead of react-select]]

import { router, useForm } from "@inertiajs/react";
import { Search } from "lucide-react";
import { useMemo, useState } from "react";
import type { sway } from "sway";

import { Button } from "app/frontend/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "app/frontend/components/ui/dialog";
import { Input } from "app/frontend/components/ui/input";
import { Label } from "app/frontend/components/ui/label";
import { RadioGroup, RadioGroupItem } from "app/frontend/components/ui/radio-group";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "app/frontend/components/ui/select";
import { Textarea } from "app/frontend/components/ui/textarea";
import { ROUTES } from "app/frontend/sway_constants";
import { shortBillTitle } from "app/frontend/components/bill/sway_utils/billTitle";

interface IProps {
    open: boolean;
    organizationId: number;
    bills: sway.IBill[];
    membershipHref: string;
}

const NewPositionDialog: React.FC<IProps> = ({ open, organizationId, bills, membershipHref }) => {
    const [query, setQuery] = useState("");
    const form = useForm<{
        bill_id: string;
        support: "FOR" | "AGAINST";
        summary: string;
    }>({
        bill_id: "",
        support: "FOR",
        summary: "",
    });

    const filtered = useMemo(() => {
        const q = query.trim().toLowerCase();
        if (!q) return bills;
        return bills.filter((b) => {
            const hay = `${b.external_id ?? ""} ${b.title ?? ""}`.toLowerCase();
            return hay.includes(q);
        });
    }, [bills, query]);

    const handleClose = () => {
        router.visit(membershipHref, { preserveScroll: true });
    };

    const handleSubmit = (e: React.SubmitEvent<HTMLFormElement>) => {
        e.preventDefault();
        form.post(ROUTES.organizations.positions.create(organizationId), {
            preserveScroll: true,
        });
    };

    return (
        <Dialog
            open={open}
            onOpenChange={(next) => {
                if (!next) handleClose();
            }}
        >
            <DialogContent className="max-w-xl">
                <DialogHeader>
                    <DialogTitle>Add New Position</DialogTitle>
                </DialogHeader>
                <form onSubmit={handleSubmit} className="space-y-4">
                    <div className="space-y-2">
                        <Label htmlFor="position-bill">Bill</Label>
                        <div className="relative">
                            <Search
                                className="pointer-events-none absolute top-1/2 left-2 size-4 -translate-y-1/2 text-muted-foreground"
                                aria-hidden
                            />
                            <Input
                                type="search"
                                placeholder="Search bills…"
                                value={query}
                                onChange={(e) => setQuery(e.target.value)}
                                className="pl-8"
                            />
                        </div>
                        <Select value={form.data.bill_id} onValueChange={(v) => form.setData("bill_id", v)}>
                            <SelectTrigger id="position-bill" className="w-full">
                                <SelectValue placeholder="Select a bill…" />
                            </SelectTrigger>
                            <SelectContent className="max-h-80">
                                {filtered.length === 0 ? (
                                    <div className="px-3 py-2 text-sm text-muted-foreground">No matching bills.</div>
                                ) : (
                                    filtered.map((bill) => (
                                        <SelectItem key={bill.id} value={String(bill.id)}>
                                            <span className="tabular-nums lining-nums">{bill.external_id}</span>
                                            {bill.title ? ` — ${shortBillTitle(bill.title)}` : ""}
                                        </SelectItem>
                                    ))
                                )}
                            </SelectContent>
                        </Select>
                        {form.errors.bill_id && <p className="text-xs text-destructive">{form.errors.bill_id}</p>}
                    </div>

                    <div className="space-y-2">
                        <Label>Support</Label>
                        <RadioGroup
                            value={form.data.support}
                            onValueChange={(v) => form.setData("support", v as "FOR" | "AGAINST")}
                            className="flex gap-4"
                        >
                            <div className="flex items-center gap-2">
                                <RadioGroupItem value="FOR" id="support-for" />
                                <Label htmlFor="support-for" className="cursor-pointer">
                                    FOR
                                </Label>
                            </div>
                            <div className="flex items-center gap-2">
                                <RadioGroupItem value="AGAINST" id="support-against" />
                                <Label htmlFor="support-against" className="cursor-pointer">
                                    AGAINST
                                </Label>
                            </div>
                        </RadioGroup>
                        {form.errors.support && <p className="text-xs text-destructive">{form.errors.support}</p>}
                    </div>

                    <div className="space-y-2">
                        <Label htmlFor="position-summary">Summary</Label>
                        <Textarea
                            id="position-summary"
                            rows={8}
                            value={form.data.summary}
                            onChange={(e) => form.setData("summary", e.target.value)}
                            placeholder="Why does the organization take this position?"
                        />
                        {form.errors.summary && <p className="text-xs text-destructive">{form.errors.summary}</p>}
                    </div>

                    <DialogFooter>
                        <Button type="button" variant="outline" onClick={handleClose}>
                            Close
                        </Button>
                        <Button type="submit" disabled={form.processing || !form.data.bill_id}>
                            {form.processing ? "Saving…" : "Save Position"}
                        </Button>
                    </DialogFooter>
                </form>
            </DialogContent>
        </Dialog>
    );
};

export default NewPositionDialog;
