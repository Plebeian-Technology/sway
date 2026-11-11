// @lat: [[mobile-bill-surface-components-design#BillVoteStatus]]
import React from "react";
import { View, Text } from "react-native";

import { billVoteStatus, type BillVoteDates } from "../utils/billVoteStatus";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

export interface BillVoteStatusProps {
    bill: BillVoteDates & { active?: boolean };
    className?: string;
    testID?: string;
}

export function BillVoteStatus({ bill, className = "mt-2", testID }: BillVoteStatusProps) {
    return (
        <View className={className}>
            <Text
                testID={testID ?? "bill-header-vote-status"}
                className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                accessibilityRole="text"
            >
                {billVoteStatus(bill)}
            </Text>
            {bill.active === false && bill.vote_date_time_utc ? (
                <Text
                    testID="bill-header-no-longer-in-office"
                    className="mt-1 text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark"
                    accessibilityRole="text"
                >
                    {PARITY_COPY.bill.voteStatus.maybeNoLongerInOffice}
                </Text>
            ) : null}
        </View>
    );
}

export default BillVoteStatus;
