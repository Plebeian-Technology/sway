import re

def add_property_to_test_files():
    files = [
        'worktrees/SWAY-1asmb/app/frontend/pages/__tests__/Legislator.test.tsx',
        'worktrees/SWAY-1asmb/app/frontend/pages/__tests__/LegislatorHistory.adversarial.test.tsx',
        'worktrees/SWAY-1asmb/app/frontend/pages/__tests__/LegislatorHistoryEmpiricalChallenge.test.tsx'
    ]

    for file_path in files:
        with open(file_path, 'r') as f:
            content = f.read()

        # Regex to find IAgreeable object blocks
        # This matches blocks ending with count_legislator_abstained: \d+
        
        def replacement(match):
            indent = match.group(1)
            agreed = int(match.group(2))
            disagreed = int(match.group(3))
            
            # Check if property already exists
            if "reached_ten_voter_minimum" in match.group(0):
                return match.group(0)

            reached = (agreed + disagreed) >= 10
            return f'{match.group(0)},\n{indent}reached_ten_voter_minimum: {str(reached).lower()}'

        # Pattern:
        # (\s+)count_agreed: (\d+),\n
        # \s+count_disagreed: (\d+),
        
        pattern = r'(\s+)count_agreed: (\d+),\n\s+count_disagreed: (\d+)'
        new_content = re.sub(pattern, replacement, content)
        
        with open(file_path, 'w') as f:
            f.write(new_content)
        print(f"Fixed {file_path}")

add_property_to_test_files()
