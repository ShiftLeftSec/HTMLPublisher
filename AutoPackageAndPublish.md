# Auto package and publish extension into Marketplace

The `create.sh` file would auto package this extenstion then publish the extension into your marketplace. 

This file assumes that some environment variables has been set up properly prior executing this file. Copy the tracked template with `cp .env.example .env` (`.env` is git-ignored, so your real token is never committed). The environment variables are stored in the `.env` file. `.env` file has the following variables that needs to filled in.
   1.  `AZDO_TOKEN` - PAT token of your AZDO. Make sure this token is configured to have `Organization` setting set to `All accessible organizations`.
   1. `AZDO_ORGANIZATION` - organization where the extension would be shared to.
   1. `AZDO_PUBLISHER_ID` - publisher id.
   1. `AZDO_EXTENSION_ID` - extension id.

Once the `.env` is set, excute `source .env` to set the environment variables prior to executing the `./create.sh` command.

This file would do the following:
1. Bump the extension's patch version. This reads Major/Minor/Patch from `/publishhtmlreport/task.json`, adds 1 to Patch, and writes `Major.Minor.Patch` to the following file's version numbers:
    1. `./publishhtmlreport/task.json`
    1. `./vss-extension.json`
    1. `./package.json`
    1. `./publishhtmlreport/package.json`
1. Execute `./bootstrap.sh`
1. Bundle the task (`npm run bundle` in `publishhtmlreport`), compile the tab script (`tsc -p .`) and create the vsix (`tfx extension create`)
1. Publish the `vsix` to the marketplace.

## First time publishing the extension
There is a validation problem when first time publishing, it would complain that there are more than 1000 files validation error. To overcome this, for the first time, we have to delete the `publishhtmlreport/node_modules` folder. Executing `./create.sh` with an argument (any argument) would delete it after bundling and before packaging - e.g. `./create.sh true`. Then on subsequent run, there is no need for the argument, just execute `./create.sh`

For the full step by step build from a fresh clone, see [BUILD.md](./BUILD.md).
