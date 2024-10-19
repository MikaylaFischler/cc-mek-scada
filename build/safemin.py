import os
import re

# minify files in a directory
def min_files(path):
    start_sum, end_sum = 0, 0

    for (root, _, files) in os.walk(path):
        os.makedirs('_minified/' + root, exist_ok=True)

        for f in files:
            start, end = minify(root + "/" + f)

            start_sum = start_sum + start
            end_sum = end_sum + end

    delta = start_sum - end_sum

    print(f"> done with '{path}': shrunk from {start_sum} bytes to {end_sum} bytes (saved {delta} bytes, or {(100*delta/start_sum):.2f}%)")

    return list

# minify a file
def minify(path: str):
    size_start = os.stat(path).st_size

    f = open(path, "r")
    contents = f.read()
    f.close()

    if re.search(r'--+\[(?!\[@as)+', contents) != None:
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
    f_min = open(f"_minified/{path}", "w")
    f_min.write(minified)
    f_min.close()

    size_end = os.stat(f"_minified/{path}").st_size

    print(f">> shrunk '{path}' from {size_start} bytes to {size_end} bytes (saved {size_start-size_end} bytes)")

    return size_start, size_end

# minify applications and libraries
dirs = [ 'scada-common', 'graphics', 'lockbox', 'reactor-plc', 'rtu', 'supervisor', 'coordinator', 'pocket' ]
for _, d in enumerate(dirs):
    min_files(d)

# minify root files
minify("startup.lua")
minify("initenv.lua")
minify("configure.lua")

# copy in license for build usage
lic1 = open("LICENSE", "r")
lic2 = open("_minified/LICENSE", "w")
lic2.write(lic1.read())
lic1.close()
lic2.close()
