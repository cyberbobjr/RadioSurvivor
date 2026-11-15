// JSON API of bridge/atelier_server.py. Every call answers {ok, status, code, message, ...}: `code` is translated by
// the page (i18n "code.<code>"), `message` is the server's English text used when no translation exists.

const voiceUrl = (id) => `/api/voices/${encodeURIComponent(id)}`;

export function createApi(fetchFn = fetch) {
  async function call(method, url, body = undefined, json = true) {
    let response;
    try {
      response = await fetchFn(url, {
        method,
        headers: body === undefined ? {} : { 'Content-Type': json ? 'application/json' : 'text/plain; charset=utf-8' },
        body: body === undefined ? undefined : (json ? JSON.stringify(body) : body),
        cache: 'no-store',
      });
    } catch (err) {
      return { ok: false, status: 0, code: 'offline', message: String(err) };
    }
    const type = response.headers.get('Content-Type') || '';
    if (type.startsWith('application/json')) return { status: response.status, ...(await response.json()) };
    return { ok: response.ok, status: response.status, code: response.ok ? 'ok' : 'http_error', text: await response.text() };
  }

  return {
    voices: () => call('GET', '/api/voices'),
    read: (id) => call('GET', voiceUrl(id)),
    save: (id, text) => call('PUT', voiceUrl(id), text, false),
    remove: (id) => call('DELETE', voiceUrl(id)),
    duplicate: (id, newId) => call('POST', `${voiceUrl(id)}/duplicate`, { newId }),
    silence: (id) => call('POST', `${voiceUrl(id)}/remove`, {}),
    restore: (id) => call('POST', `${voiceUrl(id)}/restore`, {}),
    importSheet: (filename, text, newId = undefined) => call('POST', '/api/import', { filename, text, newId }),
    exportUrl: (id) => `${voiceUrl(id)}/export`,
    verdicts: () => call('GET', '/api/verdicts'),
    journal: (since) => call('GET', `/api/log?since=${encodeURIComponent(String(since))}`),
    surveys: () => call('GET', '/api/surveys'),   // E22-T08: places recorded in game, newest first
    status: () => call('GET', '/api/status'),
    // E22-T06: the bridge's AI ({ok:false, code:'ai_unavailable'} without configuration)
    aiPersonality: (body) => call('POST', '/api/ai/personality', body),
    aiStory: (body) => call('POST', '/api/ai/story', body),
    aiTry: (body) => call('POST', '/api/ai/try', body),
  };
}
