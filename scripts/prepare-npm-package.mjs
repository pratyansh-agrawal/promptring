import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const stage = join(root, ".npm-package");
const packageJson = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));

rmSync(stage, { force: true, recursive: true });
mkdirSync(stage, { recursive: true });

for (const entry of packageJson.files) {
  if (entry === "README.md") continue;

  const source = join(root, entry);
  const destination = join(stage, entry);
  mkdirSync(dirname(destination), { recursive: true });
  cpSync(source, destination, { recursive: true });
}

cpSync(join(root, "npm", "README.md"), join(stage, "README.md"));

packageJson.scripts = {
  postinstall: packageJson.scripts.postinstall,
};
writeFileSync(
  join(stage, "package.json"),
  `${JSON.stringify(packageJson, null, 2)}\n`,
);

console.log(`Prepared npm package ${packageJson.name}@${packageJson.version}`);
