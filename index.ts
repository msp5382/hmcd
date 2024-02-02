import express from "express";
import fs from "fs";
import path from "path";
import { configDotenv } from "dotenv";
import { $ } from "bun";
import { simpleGit } from "simple-git";
import type { SimpleGit, SimpleGitOptions } from "simple-git";
configDotenv();

const { GH_USER, GH_PAT, REPO, WORK_DIR, COMPOSE_LOCATION, PORT, BRANCH } =
  process.env;

const options: Partial<SimpleGitOptions> = {
  baseDir: process.cwd(),
  binary: "git",
  maxConcurrentProcesses: 6,
  trimmed: false,
  config: [`user.name=${GH_USER}`, `user.password=${GH_PAT}`],
};

const git: SimpleGit = simpleGit(options);

const app = express();

const workDir = path.join(import.meta.dir, WORK_DIR as string);

const afterClone = async () => {
  const composeLocation = path.join(workDir, COMPOSE_LOCATION as string);

  const composeFilename = composeLocation.split(path.sep).pop();
  try {
    await $`docker login -u ${GH_USER} -p ${GH_PAT} ghcr.io`;
    await $`docker-compose -f ${composeFilename} up -d`
      .cwd(path.dirname(composeLocation))
      .env({
        BUILDKIT_PROGRESS: "plain",
      });
  } catch (error) {
    console.error(error);
  }
};

app.get("/webhook", async (req, res) => {
  try {
    if (!fs.existsSync(workDir)) {
      fs.mkdirSync(workDir);
      await git.cwd(workDir).clone(REPO as string, workDir);
      console.log("Cloned the repo");
      res.send("Webhook received!");
      afterClone();
      return;
    }
    await git.cwd(workDir).pull("origin", BRANCH as string);
    console.log("Pulled latest changes from the repo");
    res.send("Webhook received!");
    afterClone();
  } catch (error) {
    console.error(error);
  }
});

const port = PORT || 3000;

app.listen(port, () => {
  console.log(`HMCD is running on port ${port}!`);
});
