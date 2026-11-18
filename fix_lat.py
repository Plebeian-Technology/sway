
import sys

file_path = '/Users/dave/plebtech/sway/lat.md/explanation/explanation.md'
with open(file_path, 'r') as f:
    lines = f.readlines()

new_lines = [
    '- [Organization track control](organization-track-control.md) — The action-button design for organization tracking and notification controls.\n',
    '- [Organization track control state machine](organization-track-control-state-machine.md) — OrganizationFollowControl.tsx design notes for follow/unfollow and notification states.\n',
    '- [Organization track control test regressions](organization-track-control-test-regressions.md) — Two regression guards for the OrganizationFollowControl: member click handling and picker routing.\n',
    '- [Organization track notification design](organization-track-notification-design.md) — Notification preference seeding from user defaults and organization-specific overrides.\n',
    '- [Organization tracks controller access model](organization-tracks-controller-access-model.md) — Access and write-scope model for the controller handling organization follows and settings.\n'
]

new_content = []
for line in lines:
    new_content.append(line)
    if 'Android app links' in line:
        new_content.extend(new_lines)

with open(file_path, 'w') as f:
    f.writelines(new_content)
