import type { ILegislativeSessionOption } from "app/frontend/components/bill/list-layouts/types";

interface IProps {
    id: string;
    className?: string;
    sessions: readonly ILegislativeSessionOption[];
    value?: number | null;
    onChange?: (sessionId: number) => void;
}

const BillsSessionSelect: React.FC<IProps> = ({ id, className, sessions, value, onChange }) => (
    <select
        id={id}
        className={className}
        data-testid="select-legislative-session"
        value={value ?? ""}
        onChange={(event) => {
            const nextId = Number(event.target.value);
            if (Number.isInteger(nextId) && nextId > 0) {
                onChange?.(nextId);
            }
        }}
    >
        {sessions.map((session) => (
            <option key={session.id} value={session.id}>
                {session.active ? `${session.name} (Current)` : session.name}
            </option>
        ))}
    </select>
);

export default BillsSessionSelect;
