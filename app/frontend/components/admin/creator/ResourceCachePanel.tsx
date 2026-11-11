import { useMemo } from "react";
import { Badge } from "app/frontend/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "app/frontend/components/ui/table";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "app/frontend/components/ui/tooltip";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import { relativeTime } from "app/frontend/sway_utils/datetimes";
import type { ResourceCacheRow, ResourceCacheTier } from "app/frontend/types/bill_creator";
import { TIER_ORDER, TIER_LABELS } from "app/frontend/components/admin/creator/constants/resource_cache_tiers";

interface IProps {
    mirrors: ResourceCacheRow[];
}

const ResourceCachePanel: React.FC<IProps> = ({ mirrors }) => {
    // @lat: [[per-bill-grid-virtualization#Why ResourceCachePanel indexes mirrors by tier]]
    const byTier = useMemo(() => {
        const map = new Map<ResourceCacheTier, ResourceCacheRow>();
        for (const m of mirrors) {
            map.set(m.tier, m);
        }
        return map;
    }, [mirrors]);

    return (
        <Card data-testid="resource-cache-panel" className="max-w-full overflow-hidden">
            <CardHeader>
                <div className="flex items-center gap-1.5">
                    <CardTitle>Resource Cache</CardTitle>
                    <FeatureInfo note="pipeline.resourceCache" />
                </div>
            </CardHeader>
            <CardContent className="p-0">
                {/* @lat: [[per-bill-grid-virtualization#Why ResourceCachePanel wraps its table in one TooltipProvider]] */}
                <TooltipProvider delayDuration={150}>
                    <div className="max-w-full overflow-x-auto">
                        <Table>
                            <TableHeader>
                                <TableRow>
                                    <TableHead className="w-40">Tier</TableHead>
                                    <TableHead>Last generated</TableHead>
                                    <TableHead className="w-32">Version</TableHead>
                                    <TableHead className="w-32">Status</TableHead>
                                </TableRow>
                            </TableHeader>
                            <TableBody>
                                {TIER_ORDER.map((tier) => {
                                    const row = byTier.get(tier);
                                    if (!row) {
                                        return (
                                            <TableRow key={tier} data-testid={`tier-row-${tier}`}>
                                                <TableCell className="text-muted-foreground">
                                                    {TIER_LABELS[tier]}
                                                </TableCell>
                                                <TableCell className="text-muted-foreground">—</TableCell>
                                                <TableCell className="text-muted-foreground">—</TableCell>
                                                <TableCell className="text-muted-foreground">Not cached</TableCell>
                                            </TableRow>
                                        );
                                    }
                                    return (
                                        <TableRow key={tier} data-testid={`tier-row-${tier}`}>
                                            <TableCell>{TIER_LABELS[tier]}</TableCell>
                                            <TableCell>
                                                <Tooltip>
                                                    <TooltipTrigger asChild>
                                                        <span>{relativeTime(row.last_generated_at)}</span>
                                                    </TooltipTrigger>
                                                    <TooltipContent>{row.last_generated_at}</TooltipContent>
                                                </Tooltip>
                                            </TableCell>
                                            <TableCell>{row.version_id ?? "—"}</TableCell>
                                            <TableCell>
                                                {row.stale ? (
                                                    <Badge variant="stamp" tone="warning">
                                                        Stale
                                                    </Badge>
                                                ) : (
                                                    <Badge variant="solid" tone="neutral">
                                                        Fresh
                                                    </Badge>
                                                )}
                                            </TableCell>
                                        </TableRow>
                                    );
                                })}
                            </TableBody>
                        </Table>
                    </div>
                </TooltipProvider>
            </CardContent>
        </Card>
    );
};

export default ResourceCachePanel;
