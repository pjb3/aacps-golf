function workflowRunsUrl(env) {
  return `https://api.github.com/repos/${encodeURIComponent(env.GITHUB_OWNER)}/${encodeURIComponent(env.GITHUB_REPO)}/actions/workflows/${encodeURIComponent(env.WORKFLOW_ID)}/runs?branch=${encodeURIComponent(env.BRANCH || "main")}&per_page=20`;
}

function dispatchUrl(env) {
  return `https://api.github.com/repos/${encodeURIComponent(env.GITHUB_OWNER)}/${encodeURIComponent(env.GITHUB_REPO)}/actions/workflows/${encodeURIComponent(env.WORKFLOW_ID)}/dispatches`;
}

function githubHeaders(env) {
  return {
    "Accept": "application/vnd.github+json",
    "Authorization": `Bearer ${env.GITHUB_TOKEN}`,
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "aacps-golf-build-monitor",
  };
}

async function dispatchWorkflow(env, scheduledTime) {
  if (!env.GITHUB_TOKEN) throw new Error("GITHUB_TOKEN secret is not configured");

  const runsResponse = await fetch(workflowRunsUrl(env), { headers: githubHeaders(env) });
  if (!runsResponse.ok) {
    throw new Error(`GitHub run-history check failed (${runsResponse.status}): ${await runsResponse.text()}`);
  }
  const { workflow_runs: runs = [] } = await runsResponse.json();
  const now = Date.now();
  const recentRun = runs.find((run) => {
    const started = Date.parse(run.run_started_at || run.created_at);
    const recent = Number.isFinite(started) && now - started >= 0 && now - started <= 8 * 60 * 1000;
    return recent && (run.status !== "completed" || run.conclusion === "success");
  });

  // The native Actions schedule remains enabled as a fallback. Skip this
  // dispatch when it or another trigger has already completed recently.
  if (recentRun) {
    console.log(`Recent workflow run ${recentRun.id} (${recentRun.event}, ${recentRun.status}); skipping dispatch`);
    return;
  }

  const response = await fetch(dispatchUrl(env), {
    method: "POST",
    headers: {
      ...githubHeaders(env),
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ ref: env.BRANCH || "main" }),
  });

  // GitHub returns 204 when it accepts a workflow dispatch.
  if (response.status !== 204) {
    const detail = await response.text();
    throw new Error(`GitHub dispatch failed (${response.status}): ${detail}`);
  }
  console.log(`Dispatched ${env.GITHUB_OWNER}/${env.GITHUB_REPO}/${env.WORKFLOW_ID} for ${scheduledTime}`);
}

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(dispatchWorkflow(env, new Date(event.scheduledTime).toISOString()));
  },

  // Read-only health endpoint. No dispatch can be triggered over HTTP.
  async fetch() {
    return new Response("AACPS Golf build monitor is disabled.", {
      status: 503,
      headers: { "Content-Type": "text/plain; charset=utf-8" },
    });
  },
};
