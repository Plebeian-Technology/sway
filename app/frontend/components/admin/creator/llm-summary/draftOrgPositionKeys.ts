import { uniqueStableKeys } from "app/frontend/sway_utils/uniqueStableKeys";
import type { TDraftOrgPosition } from "app/frontend/components/admin/creator/llm-summary/types";

// @lat: [[unique-stable-keys-react-list-identity#draftOrgPositionKeys]]
export const draftOrgPositionKeys = (positions: TDraftOrgPosition[]): string[] =>
    uniqueStableKeys(
        positions.map(
            (position) => position.draft_token ?? `${position.org_name} ${position.stance} ${position.summary}`,
        ),
    );
