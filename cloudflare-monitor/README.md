# AACPS Golf build monitor

This Worker source provides an optional independent trigger for the existing
GitHub Actions build and deploy. The Worker is currently disabled: its Cron
Trigger has been removed and its GitHub token secret has been deleted.

## Reactivate

1. Create a fine-grained personal access token for `pjb3/aacps-golf` with
   **Actions: read and write** repository permissions.
2. In `wrangler.jsonc`, change `"crons": []` to
   `"crons": ["*/10 * * * *"]`.
3. From this directory, store the token as a Cloudflare Worker secret:

   ```sh
   wrangler secret put GITHUB_TOKEN
   ```

   Wrangler prompts for the value; do not put the token in a command, source
   file, or chat message.
4. Deploy the Worker and its Cron Trigger:

   ```sh
   wrangler deploy
   ```

The trigger runs every ten minutes in UTC. The Worker only dispatches the
workflow; GitHub Actions still runs the Ruby refresh, Jekyll build, and Pages
deployment. View invocation logs with `wrangler tail`.
