import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildDiscordPayload,
  buildNotification,
  escapeDiscordMarkdown,
  extractReleaseHighlights,
  sendDiscordNotification,
  truncate,
} from './discord-notify.mjs';

const repository = { full_name: 'owner/Kairos' };
const sender = { login: 'developer' };
const release = {
  tag_name: 'v0.2.0-beta.1',
  prerelease: true,
  html_url: 'https://github.com/owner/Kairos/releases/tag/v0.2.0-beta.1',
  body: '- Added automation.',
  assets: [{
    name: 'Kairos-0.2.0-beta.1.dmg',
    browser_download_url: 'https://github.com/owner/Kairos/releases/download/v0.2.0-beta.1/Kairos-0.2.0-beta.1.dmg',
  }],
};

function response(status, body, retryAfter) {
  return {
    ok: status >= 200 && status < 300,
    status,
    headers: new Headers(retryAfter === undefined ? {} : { 'Retry-After': String(retryAfter) }),
    json: async () => body,
  };
}

test('normalizes whitespace, truncates text, and escapes Discord markdown', () => {
  assert.equal(truncate('line one\nline two', 30), 'line one line two');
  assert.equal(truncate('A'.repeat(10), 5), 'AAAA…');
  assert.equal(escapeDiscordMarkdown('**bold** [link](url) > quote'), '\\*\\*bold\\*\\* \\[link\\]\\(url\\) \\> quote');
});

test('builds push, pull request, issue, comment, and review notifications', () => {
  const sha = 'a'.repeat(40);
  const push = buildNotification('push', {
    repository,
    sender,
    ref: 'refs/heads/main',
    after: sha,
    size: 2,
    head_commit: { message: 'feat: release' },
  });
  assert.equal(push.title, 'Kairos 代码已推送');
  assert.equal(push.color, 'blue');

  const pullRequest = buildNotification('pull_request_target', {
    repository,
    sender,
    action: 'closed',
    pull_request: { number: 7, title: 'Ship', state: 'closed', merged: true },
  });
  assert.equal(pullRequest.title, 'Kairos PR 已合并');
  assert.equal(pullRequest.color, 'green');

  for (const [eventName, event] of [
    ['issues', { repository, sender, action: 'opened', issue: { number: 2, title: 'Issue' } }],
    ['issue_comment', {
      repository,
      sender,
      issue: { number: 2, title: 'Issue' },
      comment: { body: 'Comment' },
    }],
    ['pull_request_review', {
      repository,
      sender,
      pull_request: { number: 3, title: 'PR' },
      review: { state: 'approved' },
    }],
  ]) {
    const notification = buildNotification(eventName, event);
    assert.match(notification.title, /^Kairos /);
    assert.ok(notification.button.url);
  }
});

test('preserves workflow filtering and colors', () => {
  assert.equal(buildNotification('workflow_run', {
    repository,
    workflow_run: { name: 'CI', conclusion: 'success', event: 'push', head_branch: 'feature' },
  }), null);
  assert.equal(buildNotification('workflow_run', {
    repository,
    workflow_run: { name: 'Release', conclusion: 'success', event: 'workflow_run', head_branch: 'main' },
  }), null);

  const ciRequested = buildNotification('workflow_run', {
    repository,
    action: 'requested',
    workflow_run: {
      name: 'CI',
      event: 'pull_request',
      head_branch: 'feature',
      head_sha: 'a'.repeat(40),
      run_number: 12,
      html_url: 'https://github.com/owner/Kairos/actions/runs/12',
    },
  });
  assert.equal(ciRequested.title, 'Kairos CI 已触发');
  assert.equal(ciRequested.color, 'blue');

  const releaseFailure = buildNotification('workflow_run', {
    repository,
    workflow_run: { name: 'Release', conclusion: 'failure', head_branch: 'main' },
  });
  assert.equal(releaseFailure.color, 'red');
});

test('builds release and packaging notifications with Kairos product facts', () => {
  const releaseNotification = buildNotification('release', { repository, sender, release });
  assert.equal(releaseNotification.title, 'Kairos 0.2.0-beta.1 发布成功');
  assert.equal(releaseNotification.color, 'green');
  assert.match(releaseNotification.details.join('\n'), /DNS Helper/);
  assert.equal(releaseNotification.secondaryButton.text, '下载 DMG');

  const packaging = buildNotification('repository_dispatch', {
    repository,
    sender,
    action: 'release_started',
    client_payload: {
      version: '0.2.0-beta.1',
      prerelease: true,
      dmg_name: 'Kairos-0.2.0-beta.1.dmg',
      sha: 'a'.repeat(40),
      run_url: 'https://github.com/owner/Kairos/actions/runs/12',
    },
  });
  assert.equal(packaging.title, 'Kairos 0.2.0-beta.1 开始打包');
  assert.equal(packaging.color, 'blue');
  assert.ok(packaging.details.includes('架构：arm64'));
  assert.ok(packaging.details.includes('系统：macOS 26+'));
  assert.ok(packaging.details.includes('组件：Kairos.app + DNS Helper'));
});

test('builds a release-published dispatch with Kairos product facts', () => {
  const notification = buildNotification('repository_dispatch', {
    repository,
    sender,
    action: 'release_published',
    client_payload: {
      version: '0.2.0-beta.1',
      prerelease: true,
      dmg_name: 'Kairos-0.2.0-beta.1.dmg',
      changelog: '- Added automation.',
      release_url: 'https://github.com/owner/Kairos/releases/tag/v0.2.0-beta.1',
      download_url: 'https://github.com/owner/Kairos/releases/download/v0.2.0-beta.1/Kairos-0.2.0-beta.1.dmg',
    },
  });
  const payload = buildDiscordPayload(notification, 'Kairos');
  assert.equal(notification.title, 'Kairos 0.2.0-beta.1 发布成功');
  assert.equal(notification.color, 'green');
  assert.ok(notification.details.includes('组件：Kairos.app + DNS Helper'));
  assert.match(payload.embeds[0].description, /\[下载 DMG\]/);
});

test('builds one safe Discord embed with title URL, actions, colors, and disabled mentions', () => {
  const notification = buildNotification('release', { repository, sender, release });
  const payload = buildDiscordPayload(notification, 'Kairos');
  const embed = payload.embeds[0];

  assert.equal(payload.username, 'Kairos');
  assert.deepEqual(payload.allowed_mentions, { parse: [] });
  assert.equal(embed.color, 0x57F287);
  assert.equal(embed.url, release.html_url);
  assert.match(embed.description, /\[查看版本\]\(https:\/\/github\.com\/owner\/Kairos\/releases\/tag\/v0\.2\.0-beta\.1\)/);
  assert.match(embed.description, /\[下载 DMG\]\(https:\/\/github\.com\/owner\/Kairos\/releases\/download\/v0\.2\.0-beta\.1\/Kairos-0\.2\.0-beta\.1\.dmg\)$/);
  assert.equal('components' in payload, false);
});

test('escapes external Discord markdown and rejects untrusted action URLs', () => {
  const notification = buildNotification('issues', {
    repository,
    sender,
    action: 'opened',
    issue: {
      number: 9,
      title: '**bold** [link](https://example.com) @everyone',
      html_url: 'https://example.com/issue/9',
    },
  });
  const payload = buildDiscordPayload(notification, 'Kairos');
  const embed = payload.embeds[0];

  assert.match(embed.description, /\\\*\\\*bold\\\*\\\* \\\[link\\\]\\\(https:\/\/example\.com\\\)/);
  assert.equal(embed.url, 'https://github.com/owner/Kairos');
  assert.match(embed.description, /\[查看 Issue\]\(https:\/\/github\.com\/owner\/Kairos\)$/);
});

test('keeps three release highlights', () => {
  assert.deepEqual(extractReleaseHighlights('- One\n- Two\nText\n* Three\n- Four'), [
    '• One',
    '• Two',
    '• Three',
  ]);
});

test('accepts every 2xx response and retains webhook query parameters with wait=true', async () => {
  let requestUrl;
  await sendDiscordNotification({}, 'https://discord.com/api/webhooks/id/token?thread_id=42', {
    fetchImplementation: async (url) => {
      requestUrl = new URL(url);
      return response(204);
    },
  });
  assert.equal(requestUrl.searchParams.get('thread_id'), '42');
  assert.equal(requestUrl.searchParams.get('wait'), 'true');

  await sendDiscordNotification({}, 'https://discord.com/api/webhooks/id/token', {
    fetchImplementation: async () => response(201),
  });
});

test('retries Discord 429 using Retry-After and retry_after seconds', async () => {
  const responses = [
    response(429, {}, 0.25),
    response(429, { retry_after: 0.5 }),
    response(204),
  ];
  const waits = [];
  await sendDiscordNotification({}, 'https://discord.com/api/webhooks/id/token', {
    fetchImplementation: async () => responses.shift(),
    wait: async (milliseconds) => waits.push(milliseconds),
  });
  assert.deepEqual(waits, [250, 500]);
});

test('retries network and 5xx failures with exponential backoff', async () => {
  let networkAttempts = 0;
  const networkWaits = [];
  await sendDiscordNotification({}, 'https://discord.com/api/webhooks/id/token', {
    fetchImplementation: async () => {
      networkAttempts += 1;
      if (networkAttempts === 1) throw new Error('offline');
      return response(204);
    },
    wait: async (milliseconds) => networkWaits.push(milliseconds),
  });
  assert.deepEqual(networkWaits, [250]);

  const serverWaits = [];
  const responses = [response(503), response(204)];
  await sendDiscordNotification({}, 'https://discord.com/api/webhooks/id/token', {
    fetchImplementation: async () => responses.shift(),
    wait: async (milliseconds) => serverWaits.push(milliseconds),
  });
  assert.deepEqual(serverWaits, [250]);
});

test('does not retry permanent Discord 4xx responses', async () => {
  let attempts = 0;
  await assert.rejects(sendDiscordNotification({}, 'https://discord.com/api/webhooks/id/token', {
    fetchImplementation: async () => {
      attempts += 1;
      return response(400);
    },
    wait: async () => assert.fail('should not wait'),
  }));
  assert.equal(attempts, 1);
});

test('rejects an invalid webhook URL without echoing its value', async () => {
  const invalidWebhook = 'not-a-url-with-secret-token';
  await assert.rejects(
    sendDiscordNotification({}, invalidWebhook),
    (error) => error.message === 'DISCORD_WEBHOOK_URL is invalid.' && !error.message.includes(invalidWebhook),
  );
});
