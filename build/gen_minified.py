import os
import re
import sys

#
# definitions/globals
#

DIRS = [ 'scada-common', 'graphics', 'lockbox', 'reactor-plc', 'rtu', 'supervisor', 'coordinator', 'pocket' ]

# can be overridden
OUTPUT = './_minified'

# ANSI Color Codes
BLACK = "\033[30m"
RED = "\033[31m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
BLUE = "\033[34m"
MAGENTA = "\033[35m"
CYAN = "\033[36m"
WHITE = "\033[37m"
BOLD = "\033[1m"
RESET = "\033[0m"

skipped_comments = 0

#
# functions
#

# minify files in a directory
def min_files(path):
    start_sum, end_sum = 0, 0

    for (root, _, files) in os.walk(path):
        os.makedirs(OUTPUT + '/' + root, exist_ok=True)

        for f in files:
            start, end = minify(root + '/' + f)

            start_sum = start_sum + start
            end_sum   = end_sum + end

    delta = start_sum - end_sum

    print(f"> {BOLD}done with '{path}': shrunk from {start_sum} bytes to {end_sum} bytes (saved {delta} bytes, or {(100 * delta / start_sum):.2f}%){RESET}")

    summary = { "path": path, "start": start_sum, "end": end_sum, "delta": delta, "percent": f"-{(100 * delta / start_sum):.2f}%" }

    return summary

# minify a file
def minify(path: str, skip_lines = 0):
    global skipped_comments

    size_start = os.path.getsize(path)

    f = open(path, "r")
    contents = f.read()
    f.close()

    # allow skipping header lines (may contain things like multiline comments)
    skipped = ""
    if skip_lines > 0:
        lines    = contents.splitlines(keepends=True)
        skipped  = ''.join(lines[:skip_lines])
        contents = contents[len(skipped):]

    # remove --[[@as type]] hints before anything, since it would detect as multiline comments
    contents = re.sub(r' --+\[.+]]', '', contents)

    if re.search(r'--+\[+', contents) != None:
        # absolutely not dealing with lua multiline comments
        # - there are more important things to do
        # - this minification is intended to be 100% safe, so working with multiline comments is asking for trouble
        # - the project doesn't use them as of writing this (except in test/), and it might as well stay that way
        raise Exception(f"no multiline comments allowed! (offending file: {path})")

    if re.search(r'\\$', contents, flags=re.MULTILINE) != None:
        # '\' allows for multiline strings, which would require reverting to processing syntax line by line to support them
        raise Exception(f"no escaping newlines! (offending file: {path})")

    # drop comment-only lines (which can include quotes)
    minified = re.sub(r'^[ \t]*--+.*', '', contents, flags=re.MULTILINE)

    # drop other comments, unless the line has quotes, because quotes are scary
    # (quotes are scary since we could actually be inside a string: "-- ..." shouldn't get deleted)
    # -> whitespace before '--' and anything after that, which includes '---' comments
    minified = re.sub(r'\s*--+(?!.*[\'"]).*', '', minified)

    # drop leading whitespace on each line
    minified = re.sub(r'^[ \t]+', '', minified, flags=re.MULTILINE)

    # drop blank lines
    while minified != re.sub(r'\n\n', '\n', minified):
        minified = re.sub(r'\n\n', '\n', minified)

    # write the minified file
    f_min = open(f"{OUTPUT}/{path}", "w")
    f_min.write(skipped + minified)
    f_min.close()

    size_end = os.path.getsize(f"{OUTPUT}/{path}")

    print(f">> {BLACK}shrunk '{path}' from {size_start} bytes to {size_end} bytes (saved {size_start - size_end} bytes){RESET}")

    # check for potential comments not deleted
    for lineno, line in enumerate(contents.splitlines(), start=1):
        if re.match(r'^[ \t]*--', line):
            continue
        if '--' not in line:
            continue

        stripped = re.sub(r'\s*--+(?!.*[\'"]).*', '', line)
        if stripped == line:
            skipped_comments = skipped_comments + 1
            print(f">> {YELLOW}{path}:{lineno}: this may or may not be a comment, so it was not deleted: \n\t{BOLD}{line.strip()}{RESET}")

    return size_start, size_end

#
# main
#

if __name__ == "__main__":
    # parse arguments
    deployment = "--deployment" in sys.argv

    # override output if specified
    for arg in sys.argv[1:]:
        if not arg.startswith("-"):
            OUTPUT = sys.argv[1]
            break

    if not os.path.exists(OUTPUT):
        raise FileNotFoundError(f"{OUTPUT} does not exist")

    # minify applications and libraries
    summaries = []
    for _, d in enumerate(DIRS):
        summaries.append(min_files(d))

    # minify root files
    start_sum = 0
    end_sum   = 0

    for start, end in (minify("startup.lua"), minify("initenv.lua"), minify("configure.lua")):
        start_sum += start
        end_sum   += end

    if deployment:
        start, end = minify("ccmsi.lua", 16)
        start_sum += start
        end_sum   += end

    delta = start_sum - end_sum

    print(f"> {BOLD}done with 'root': shrunk from {start_sum} bytes to {end_sum} bytes (saved {delta} bytes, or {(100*delta/start_sum):.2f}%){RESET}")
    summaries.append({ "path": "root", "start": start_sum, "end": end_sum, "delta": delta, "percent": f"-{(100*delta/start_sum):.2f}%" })

    # copy in license for build usage
    lic_a = open("LICENSE", "r")
    lic_b = open(f"{OUTPUT}/LICENSE", "w")
    lic_b.write(lic_a.read())
    lic_a.close()
    lic_b.close()

    print(f"> {BOLD}minifier finished with {skipped_comments} skipped comment-like line(s){RESET}")

    # sumary header
    print(f"\n{BOLD}{'Resource':<15} {'Original':>15} {'New':>14} {'Saved':>18} {'Percentage':>17}{RESET}")
    print("-" * 85)

    component_size     = {}
    component_size_min = {}

    # print summary
    for s in summaries:
        print(
            f"{BLUE}{s['path']:<15}{RESET}"
            f"{s['start']:>12,} bytes"
            f"{s['end']:>12,} bytes"
            f"{GREEN}{s['delta']:>12,}{RESET} bytes"
            f"{CYAN}{s['percent']:>12}{RESET}"
        )

        component_size[s['path']] = s['start']
        component_size_min[s['path']] = s['end']

    # disk utilization header
    print(f"\n{BOLD}{'System':<17} {'Disk Utilization':>22} {'Free':>30} {'Percentage':>33}{RESET}")
    print("-" * 112)

    computer_space = 1000000
    common         = component_size['scada-common'] + component_size['graphics'] + component_size['lockbox'] + component_size['root'] + os.path.getsize(f"{OUTPUT}/LICENSE")
    common_min     = component_size_min['scada-common'] + component_size_min['graphics'] + component_size_min['lockbox'] + component_size_min['root'] + os.path.getsize(f"{OUTPUT}/LICENSE")

    # estimated disk utilization
    for dev in [ "reactor-plc", "rtu", "supervisor", "coordinator", "pocket" ]:
        size            = common + component_size[dev]
        size_min        = common_min + component_size_min[dev]
        percent         = 100 * size / computer_space
        percent_min     = 100 * size_min / computer_space
        percent_str     = f"{percent:.2f}%"
        percent_str_min = f"{percent_min:.2f}%"

        if percent >= 90:
            color = RED
        elif percent >= 80:
            color = MAGENTA
        elif percent >= 65:
            color = YELLOW
        elif percent >= 50:
            color = CYAN
        else:
            color = GREEN

        if percent_min >= 90:
            color_min = RED
        elif percent_min >= 80:
            color_min = MAGENTA
        elif percent_min >= 65:
            color_min = YELLOW
        elif percent_min >= 50:
            color_min = CYAN
        else:
            color_min = GREEN

        print(
            f"{BLUE}{dev:<15}{RESET}"
            f"{BLACK}{size:>8,} bytes{RESET}"
            "  -> "
            f"{size_min:>8,} bytes"
            f"{BLACK}{(computer_space - size):>12,} bytes{RESET}"
            "  -> "
            f"{(computer_space - size_min):>8,} bytes"
            f"{color}{percent_str:>12}{RESET}"
            "  -> "
            f"{color_min}{percent_str_min:>7}{RESET}"
        )
