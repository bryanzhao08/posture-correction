// Changes the beta password: npm run set-password -- "new password"
// Writes only the hash into src/config.ts; commit and push to apply.
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";

const pw = process.argv.slice(2).join(" ");
if (pw.length < 6) {
  console.error('Usage: npm run set-password -- "new password"   (at least 6 characters)');
  process.exit(1);
}
const file = new URL("../src/config.ts", import.meta.url);
const hash = createHash("sha256").update("formcoach-beta:" + pw).digest("hex");
const src = readFileSync(file, "utf8");
const out = src.replace(/passwordHash: "[0-9a-f]*"/, `passwordHash: "${hash}"`);
if (out === src) {
  console.error("passwordHash not found in src/config.ts");
  process.exit(1);
}
writeFileSync(file, out);
console.log("Beta password updated in src/config.ts. Commit and push to main to apply it to the site.");
