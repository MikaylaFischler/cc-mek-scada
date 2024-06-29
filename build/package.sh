#!/bin/bash

# Create zips to attach to GitHub releases.
# These can be extracted onto a computer and will include all files CCMSI would otherwise install.

tag=$(git describe --tags)
apps=(coordinator pocket reactor-plc rtu supervisor)

for app in "${apps[@]}" do
    mkdir ${tag}_${app}
    cp -R $app scada-common graphics lockbox configure.lua initenv.lua startup.lua LICENSE ${tag}_${app}
    zip -r ${tag}_${app}.zip ${tag}_${app}
    rm -R ${tag}_${app}
done
