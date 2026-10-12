# AACPS Golf build monitor

This Worker provides an independent 10-minute trigger for the existing GitHub
Actions build and deploy. It checks the workflow's recent run history first and
skips dispatch when a run is already active or recently succeeded. If a recent
run failed, the next monitor tick attempts another dispatch. The GitHub cron
schedule remains enabled as a fallback.

## Deploy

1. Create a fine-grained personal access token for `pjb3/aacps-golf` with
   **Actions: read and write** repository permissions.
2. From this directory, store the token as a Cloudflare Worker secret:

   ```sh
   wrangler secret put GITHUB_TOKEN
   ```

   Wrangler prompts for the value; do not put the token in a command, source
   file, or chat message.
3. Deploy the Worker and its Cron Trigger:

   ```sh
   wrangler deploy
   ```

The trigger runs every ten minutes in UTC. The Worker only dispatches the
workflow; GitHub Actions still runs the Ruby refresh, Jekyll build, and Pages
deployment. View invocation logs with `wrangler tail`.
