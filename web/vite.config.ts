import { defineConfig } from "vite";

// GitHub Pages serves the site from /<repo>/; BASE_PATH lets other hosts (Vercel) use "/".
export default defineConfig({
  base: process.env.BASE_PATH ?? "/posture-correction/",
  server: { fs: { allow: [".."] } },   // shared/sport_profiles.json lives outside web/
  build: { target: "es2022" },
});
