# Building the VSIX from a fresh clone

There are two separate paths. Pick one:

| | Path 1: Build only | Path 2: Build and publish to Azure DevOps |
| --- | --- | --- |
| Result | a `.vsix` file on disk | the `.vsix` uploaded and shared to your ADO organization |
| Parts to follow | 1, 2, 3, 4, 5, 6 | 1, 2, then **7B** (or 3-6 then **7A**) |
| Needs Docker, Node, npm | yes | yes |
| Needs a PAT and `.env` | **no** | yes (only for 7B) |
| Run `create.sh` | **never** (it publishes) | yes, for 7B |

**Starting out? Use Path 1** and ignore Part 7 until you are ready to publish.

Contents:

0. [How the build works](#0-how-the-build-works)
1. [Install prerequisites](#1-install-prerequisites)
2. [Clone the repo](#2-clone-the-repo)
3. [Generate the template files (Docker)](#3-generate-the-template-files-docker)
4. [Set the version](#4-set-the-version)
5. [Build the VSIX](#5-build-the-vsix)
6. [Verify the VSIX](#6-verify-the-vsix)
7. [Publish to Azure DevOps (Path 2 only)](#7-publish-to-azure-devops-path-2-only)
8. [Rebuilding later](#8-rebuilding-later)
9. [Troubleshooting](#9-troubleshooting)

---

## 0. How the build works

The extension ships a copy of the **JMeter HTML dashboard template** (the `sbadmin2-1.0.7`
folder, some CSS, and `jquery.tablesorter.min.js`). JMeter generates those files when it
makes a report, so we run JMeter once inside a Docker container and copy them out.
**That is the only reason Docker is involved.**

```
Part 3: ./bootstrap.sh
  download apache-jmeter-<VERSION>.tgz -> gunzip to .tar
  docker build   (Dockerfile copies in the .tar, run.sh, test.jmx)
  docker run     (run.sh runs test.jmx and writes a dashboard to /LoadReports)
  docker cp      (copy /LoadReports out of the container)
  copy sbadmin2-1.0.7/, content/css/, jquery.tablesorter.min.js into the repo root
  delete .svg fonts (Azure DevOps rejects them)
  npm install in the repo root and in publishhtmlreport/

Part 5: npm run build
  prebuild   esbuild bundles publishhtmlreport/index.ts -> taskdist/index.js (+ task.json)
  build      tsc -p .  compiles src/enhancer/tab.ts -> dist/
  postbuild  tfx extension create -> <publisher>.<extension id>-<version>.vsix
```

Everything created by Part 3 and Part 5 is git-ignored (`sbadmin2-1.0.7/`, `content/`,
`jquery.tablesorter.min.js`, `node_modules/`, `dist/`, `taskdist/`, `*.vsix`), which is why a
fresh clone cannot build until you run Part 3.

## 1. Install prerequisites

You need all of these on the build machine (for both paths). A PAT and `.env` are only needed for
publishing (Part 7B).

| Tool | Why | Check it works |
| --- | --- | --- |
| Docker engine | runs JMeter to generate the template | `docker run --rm hello-world` |
| Node.js (22 or newer works) and npm | builds the extension | `node --version && npm --version` |
| `git`, `curl`, `gunzip`, `bash`, `unzip` | clone, download, scripts, inspect the vsix | `git --version && curl --version` |

Notes:

- On Linux your user must be able to run `docker` **without sudo**. If `docker ps` says
  "permission denied": `sudo usermod -aG docker $USER`, then log out and back in.
- The machine needs internet access to `archive.apache.org` (JMeter), the npm registry,
  and Docker Hub (the `eclipse-temurin:17-jdk` base image).
- You do **not** need to install `tsc` or `tfx` globally. The scripts use the local copies from
  `node_modules`.

## 2. Clone the repo

```bash
git clone https://github.com/ShiftLeftSec/HTMLPublisher.git
cd HTMLPublisher
git checkout <branch you want to build>     # e.g. jmeter-5.6.3-and-fixes
```

All remaining commands are run from the repo root (the folder containing `bootstrap.sh`).

Confirm you are in the right place:

```bash
ls bootstrap.sh Dockerfile package.json vss-extension.json
```

## 3. Generate the template files (Docker)

### 3a. (Only if changing the JMeter version) update the version

The current version is `5.6.3`. If you want a different one, change it in **all three** files:

1. `bootstrap.sh`: `VERSION='5.6.3'`
2. `run.sh`: `VERSION='5.6.3'`
3. `Dockerfile`: `ARG VERSION="5.6.3"`

Make sure the Java in the `Dockerfile` base image (`eclipse-temurin:17-jdk`) supports that
JMeter version. Otherwise skip 3a.

### 3b. Run the bootstrap

```bash
./bootstrap.sh
```

If you get "Permission denied", run `chmod +x bootstrap.sh create.sh run.sh` and retry.

What you will see, in order:

1. `docker rm -f jmeter`: may print "No such container". That is fine.
2. curl downloads the JMeter tgz; gunzip turns it into `apache-jmeter-<VERSION>.tar`.
3. `docker build` builds the image `jmeter:latest` (first run pulls the base image, so it takes longer).
4. The `.tar` is deleted and a container named `jmeter` starts in the background.
5. `Generating template files to build extension`, then a **60 second wait** while JMeter runs
   `test.jmx` and writes the dashboard to `/LoadReports` in the container.
6. `docker cp` copies the report out and the container is removed.
7. The files are copied into the repo and the temporary `LoadReports/` folder is deleted.
8. `npm install` runs in the repo root and then in `publishhtmlreport/`.

The script ends with a `mv` of `node_modules/resolve/.github/workflows/node-4+.yml`. A
"No such file or directory" error on that line is harmless.

### 3c. Check it worked

```bash
ls -d sbadmin2-1.0.7 content/css jquery.tablesorter.min.js node_modules publishhtmlreport/node_modules
```

All five must exist. If `sbadmin2-1.0.7` is missing, the 60 second wait was probably too short
for this machine. Increase `sleep 60` in `bootstrap.sh` and re-run (Part 9 has how to inspect the container).

## 4. Set the version

Decide the new version, e.g. `1.3.7`, and set it in **all four** places. They must agree.

| File | Change |
| --- | --- |
| `package.json` | `"version": "1.3.7"` |
| `publishhtmlreport/package.json` | `"version": "1.3.7"` |
| `vss-extension.json` | `"version": "1.3.7"` |
| `publishhtmlreport/task.json` | `"version": { "Major": 1, "Minor": 3, "Patch": 7 }` |

The Marketplace rejects a version that is not higher than the one already published. A
previous build's version is visible in old vsix file names (`ls *.vsix`) and the Marketplace
publisher page.

(`create.sh` does this step automatically; see Part 7, option B.)

## 5. Build the VSIX

```bash
npm run build
```

This runs the three stages from Part 0. When it finishes there is a new file in the repo root:

```
<publisher>.<extension id>-<version>.vsix      e.g. PhilYoung.HTMLPublisher-1.3.7.vsix
```

If it fails, see Part 9. The old instruction to run `publishhtmlreport/tsc` first is no
longer needed.

## 6. Verify the VSIX

```bash
ls -la *.vsix
unzip -l PhilYoung.HTMLPublisher-1.3.7.vsix | grep -v -E "sbadmin2|node_modules"
```

The listing should contain, at least:

- `extension.vsomanifest` and `[Content_Types].xml`
- `scripts/src/enhancer/tab.js` and `scripts/publishhtmlreport/scriptFiles.js`
- `publishhtmlreport/index.js` and `publishhtmlreport/task.json`
- `index.html`, `OverTime.html`, `Throughput.html`, `ResponseTimes.html`, `CustomsGraphs.html`
- `content/css/...` and `jquery.tablesorter.min.js`
- `sbadmin2-1.0.7/...` (check with `unzip -l <file> | grep -c sbadmin2`, expect many hundreds)

If `sbadmin2-1.0.7` or `content/css` entries are missing, go back to Part 3.

**Path 1 (build only) ends here.** The `.vsix` in the repo root is your deliverable. Keep it somewhere
safe; Part 7 is only needed when you want to publish it to Azure DevOps.

## 7. Publish to Azure DevOps (Path 2 only)

**Skip this whole part if you are only building the vsix (Path 1).** Nothing above needs a
PAT, a publisher account or `.env`.

Before publishing you need a Marketplace publisher whose id matches `"publisher"` in
`vss-extension.json` (currently `PhilYoung`), and an extension id matching `"id"`
(currently `HTMLPublisher`).

Choose one.

### Option A: upload manually (after completing Parts 3-6)

Marketplace publisher page > your extension > `...` > **Update** > select the `.vsix`.

### Option B: one command (bump version, bootstrap, build, publish)

> **Warning:** `create.sh` changes the version in four files and publishes to the Marketplace.
> Do not run it for a build-only run.

`create.sh` does Parts 3b, 4, 5 and the publish in one go, so on a fresh clone you can skip
those and go straight here (Parts 1 and 2 are still required).

1. Create a personal access token (PAT) in Azure DevOps with the **Marketplace > Manage**
   scope and `Organization` set to **All accessible organizations**.
2. Create your own `.env` from the template (`cp .env.example .env`) and fill it in. `.env` is git-ignored; `.env.example` is the tracked template:

   ```bash
   export AZDO_TOKEN=<your PAT>
   export AZDO_ORGANIZATION=<organization to share the extension with>
   export AZDO_PUBLISHER_ID=<publisher id>        # e.g. PhilYoung
   export AZDO_EXTENSION_ID=<extension id>        # e.g. HTMLPublisher
   ```
3. Load it and run:

   ```bash
   source .env
   ./create.sh
   ```

   `create.sh` reads the current version from `publishhtmlreport/task.json`, bumps the **patch**
   number in all four files, runs `bootstrap.sh`, bundles the task, compiles, creates the vsix and
   publishes it. To bump major or minor, edit `task.json` by hand first (set Patch to one
   less than you want).
4. **First publish only:** the Marketplace may fail validation with "more than 1000 files". If so,
   run `./create.sh true`. The `true` argument deletes `publishhtmlreport/node_modules` after
   bundling and before packaging. Subsequent runs do not need it.

Never commit a filled-in `.env` or paste the token anywhere.

## 8. Rebuilding later

On a machine that already ran Part 3 you do **not** need Docker again unless you change the
JMeter version or delete the generated folders. The short loop is:

```bash
# edit code, then bump the version (Part 4)
npm run build
```

To start completely clean:

```bash
npm run clean                          # removes dist/ and *.vsix
rm -rf taskdist node_modules publishhtmlreport/node_modules
rm -rf sbadmin2-1.0.7 content jquery.tablesorter.min.js
docker rm -f jmeter                    # if a container was left behind
docker image rm jmeter:latest          # optional
```

Then start again from Part 3.

## 9. Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `docker: permission denied` | Add your user to the `docker` group (Part 1) |
| `COPY apache-jmeter-<VERSION>.tar` fails in `docker build` | The `.tar` must exist in the repo root at build time. `bootstrap.sh` creates it; if you run `docker build` by hand, download and `gunzip` the tgz first |
| `sbadmin2-1.0.7` not created | JMeter had not finished in 60s, or `test.jmx` failed. Inspect: `docker run -d --name jmeter -it jmeter:latest`, then `docker logs jmeter` and `docker exec -it jmeter ls /LoadReports`, then `docker rm -f jmeter` |
| curl downloads a tiny file / gunzip fails | The JMeter version in `bootstrap.sh` does not exist at archive.apache.org, or no internet |
| `npm run build` fails in `prebuild` (esbuild not found) | `publishhtmlreport/node_modules` is missing. Run `cd publishhtmlreport && npm install` |
| `tfx: not found` or `tsc: not found` | Root `node_modules` is missing. Run `npm install` in the repo root |
| Marketplace: version must be higher | Bump the version (Part 4) |
| Marketplace: more than 1000 files | `./create.sh true` (Part 7B) |
| Marketplace rejects a file name containing `+` | `find . -path '*node_modules*' -name '*+*'` and rename the file |
| `run.sh` writes `LoadReportsresults.jtl` | Known harmless typo (backslash instead of `/`). Does not affect the template files |
