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

    print(f"> {BOLD}done with '{path}': shrunk from {start_sum} bytes to {end_sum} bytes (saved {delta} bytes, or {(100*delta/start_sum):.2f}%){RESET}")

    summary = { "path": path, "start": start_sum, "end": end_sum, "delta": delta, "percent": f"-{(100*delta/start_sum):.2f}%" }

    return summary

# minify a file
def minify(path: str):
    size_start = os.stat(path).st_size

    f = open(path, "r")
    contents = f.read()
    f.close()

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

    # drop the comments, unless the line has quotes, because quotes are scary
    # (quotes are scary since we could actually be inside a string: "-- ..." shouldn't get deleted)
    # -> whitespace before '--' and anything after that, which includes '---' comments
    minified = re.sub(r'\s*--+(?!.*[\'"]).*', '', contents)

    # drop leading whitespace on each line
    minified = re.sub(r'^ +', '', minified, flags=re.MULTILINE)

    # drop blank lines
    while minified != re.sub(r'\n\n', '\n', minified):
        minified = re.sub(r'\n\n', '\n', minified)

    # write the minified file
    f_min = open(f"{OUTPUT}/{path}", "w")
    f_min.write(minified)
    f_min.close()

    size_end = os.stat(f"{OUTPUT}/{path}").st_size

    print(f">> {BLACK}shrunk '{path}' from {size_start} bytes to {size_end} bytes (saved {size_start-size_end} bytes){RESET}")

    return size_start, size_end

#
# main
#

if __name__ == "__main__":
    # override output if specified
    if len(sys.argv) > 1 and os.path.exists(sys.argv[1]):
        OUTPUT = sys.argv[1]

    summaries = []

    # minify applications and libraries
    for _, d in enumerate(DIRS):
        summaries.append(min_files(d))

    # minify root files
    minify("startup.lua")
    minify("initenv.lua")
    minify("configure.lua")

    # copy in license for build usage
    lic_a = open("LICENSE", "r")
    lic_b = open(f"{OUTPUT}/LICENSE", "w")
    lic_b.write(lic_a.read())
    lic_a.close()
    lic_b.close()

    # sumary header
    print(f"\n{BOLD}{'Resource':<15} {'Original':>15} {'New':>14} {'Saved':>18} {'Percentage':>17}{RESET}")
    print("-" * 85)

    # print summary
    for s in summaries:
        print(
            f"{BLUE}{s['path']:<15}{RESET}"
            f"{s['start']:>12,} bytes"
            f"{s['end']:>12,} bytes"
            f"{GREEN}{s['delta']:>12,}{RESET} bytes"
            f"{CYAN}{s['percent']:>12}{RESET}"
        )
