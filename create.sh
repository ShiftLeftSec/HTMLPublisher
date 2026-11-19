#!/bin/bash
# Bump the patch version, bootstrap, build the vsix and publish it to the Marketplace.
# Usage: source .env && ./create.sh [any-arg-to-delete-publishhtmlreport/node_modules-before-packaging]
set -e
removenodemodules=$1

# Read the current version from publishhtmlreport/task.json (single source of truth)
TASK_JSON=./publishhtmlreport/task.json
major=$(grep '"Major"' "$TASK_JSON" | tr -dc '0-9')
minor=$(grep '"Minor"' "$TASK_JSON" | tr -dc '0-9')
currentpatch=$(grep '"Patch"' "$TASK_JSON" | tr -dc '0-9')
echo "Current version: $major.$minor.$currentpatch"

newpatch=$((currentpatch+1))
newversion="$major.$minor.$newpatch"
echo "Bumped version: $newversion"

# macOS `sed -i` needs an empty string argument
if [[ "$OSTYPE" == "darwin"* ]]; then
    SED_INPLACE=(sed -i "")
else
    SED_INPLACE=(sed -i)
fi

echo "Patching $TASK_JSON"
"${SED_INPLACE[@]}" "s/\"Patch\":.*/\"Patch\": $newpatch/g" "$TASK_JSON"

for f in ./vss-extension.json ./package.json ./publishhtmlreport/package.json; do
    echo "Patching $f"
    "${SED_INPLACE[@]}" "s/\"version\":.*/\"version\": \"$newversion\",/g" "$f"
done

# Generate the JMeter template files (docker) and run npm install
./bootstrap.sh

# Bundle the task (esbuild). Must happen before node_modules can be removed.
(cd publishhtmlreport && npm run bundle)

if [ -n "$removenodemodules" ]; then
    rm -rf ./publishhtmlreport/node_modules
fi

# Compile the tab script and package the vsix
# (not `npm run build`: its prebuild step would re-run the bundle, which needs the
#  node_modules we may have just removed)
npx tsc -p .
npx tfx extension create

VSIX="$AZDO_PUBLISHER_ID.$AZDO_EXTENSION_ID-$newversion.vsix"

# Publish to the Marketplace
npx tfx extension publish --vsix "$VSIX" --share-with "$AZDO_ORGANIZATION" --token "$AZDO_TOKEN"

echo "Done >>>>> Published $VSIX"
