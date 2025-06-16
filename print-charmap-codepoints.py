import re
import sys

in_section = False
for line in sys.stdin.readlines():
    line = line.strip()
    if not in_section:
        if line == "CHARMAP":
            in_section = True
    elif line == "END CHARMAP":
        in_section = False
    elif (groups := re.search("^<U([0-9A-F]+)>[^.]", line)):
        # single codepoint
        codepoint = int(groups.group(1), 16)
        if codepoint < 0xd8000 or codepoint > 0xdfff:
            print(chr(codepoint))
    elif (groups := re.search(r'^<U([0-9A-F]+)>\.\.<U([0-9A-F]+)>', line)):
        # range of codepoints
        begin = int(groups.group(1), 16)
        end = int(groups.group(2), 16)
        for codepoint in range(begin, end + 1):
            if codepoint < 0xd8000 or codepoint > 0xdfff:
                print(chr(codepoint))
