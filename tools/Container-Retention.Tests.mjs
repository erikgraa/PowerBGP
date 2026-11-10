import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { collectReferences, createClient, retain, selectCandidates, validateVersions } from './Container-Retention.mjs';

const now = new Date('2026-11-10T12:00:00Z');
const old = '2026-09-01T00:00:00Z';
const recent = '2026-11-09T00:00:00Z';
const digest = id => `sha256:${id.toString(16).padStart(64, '0')}`;
const sha = `sha-${'a'.repeat(40)}`;
const imageType = 'application/vnd.oci.image.manifest.v1+json';
const indexType = 'application/vnd.oci.image.index.v1+json';
const image = { schemaVersion: 2, mediaType: imageType, config: { digest: digest(900) }, layers: [] };
const index = (...ids) => ({ schemaVersion: 2, mediaType: indexType, manifests: ids.map(id => ({ digest: digest(id), mediaType: imageType })) });
const version = (id, tags, created = old, updated = created) => ({
  id, name: digest(id), package_type: 'container', created_at: created, updated_at: updated,
  metadata: { container: { tags } },
});
const clientFixture = (versions, manifests = {}) => {
  const deleted = [];
  return {
    deleted,
    listVersions: async () => versions.filter(item => !deleted.includes(item.id)),
    readManifest: async name => manifests[name] ?? image,
    deleteVersion: async id => { deleted.push(id); },
    now, log: () => {},
  };
};

test('only expired versions containing exclusively recognized temporary tags are candidates', () => {
  const versions = [
    version(1, [sha, 'date-20260901']), version(2, ['nightly', sha]), version(3, ['latest']),
    version(4, ['1.2.3', sha]), version(5, ['v1.2.3']), version(6, ['1.2']),
    version(7, ['dispatch']), version(8, ['custom']), version(9, []),
    version(10, [sha], recent), version(11, [sha], old, recent),
    version(12, [sha, 'date-20261109']), version(13, ['date-20260230']),
    version(14, ['date-20990101']), version(15, ['sha-not-hex']),
    version(16, [sha], old, '2026-10-11T12:00:00Z'),
    version(17, ['date-20260901'], '2026-10-11T12:00:00Z'),
    version(18, ['sha-abcdef0']),
  ];
  assert.deepEqual(selectCandidates(versions, new Set(), now).map(item => item.id), [1, 18]);
});

test('preserves tagged and untagged child manifests, nested indexes and subjects', async () => {
  const versions = [version(1, ['nightly']), version(2, [sha]), version(3, []), version(4, ['date-20260901'])];
  const manifests = {
    [digest(1)]: index(2, 3, 5),
    [digest(5)]: { ...index(6), manifests: [{ digest: digest(6), mediaType: indexType }] },
    [digest(6)]: index(4),
    [digest(3)]: { ...image, subject: { digest: digest(7), mediaType: imageType } },
  };
  const refs = await collectReferences(versions, async name => manifests[name] ?? image);
  assert.deepEqual([...refs].sort(), [2, 3, 4, 5, 6, 7].map(digest).sort());
  assert.deepEqual(selectCandidates(versions, refs, now), []);
});

test('default dry run never calls DELETE; apply deletes only eligible tagged roots', async () => {
  const fixture = clientFixture([version(1, [sha]), version(2, []), version(3, ['latest'])]);
  assert.equal((await retain(fixture)).length, 1);
  assert.deepEqual(fixture.deleted, []);
  await retain({ ...fixture, apply: true });
  assert.deepEqual(fixture.deleted, [1]);
});

test('API and manifest failures prevent every deletion', async () => {
  for (const failing of [
    { listVersions: async () => { throw new Error('API denied'); } },
    { listVersions: async () => ({ versions: [] }) },
    { readManifest: async () => { throw new Error('Registry denied'); } },
    { readManifest: async () => ({ ...index(2), manifests: undefined }) },
    { readManifest: async () => ({ schemaVersion: 1 }) },
    { readManifest: async () => ({ ...index(2), manifests: [{ digest: 'bad', mediaType: imageType }] }) },
  ]) {
    const fixture = clientFixture([version(1, [sha])]);
    await assert.rejects(retain({ ...fixture, ...failing, apply: true }));
    assert.deepEqual(fixture.deleted, []);
  }
});

test('invalid inventory is rejected, including duplicate ids/digests and missing timestamps/tags', () => {
  for (const versions of [
    [version(1, [sha]), version(1, [sha])],
    [version(1, [sha]), { ...version(2, [sha]), name: digest(1) }],
    [{ ...version(1, [sha]), created_at: undefined }],
    [{ ...version(1, [sha]), updated_at: 'invalid' }],
    [{ ...version(1, [sha]), metadata: {} }],
    [{ ...version(1, [sha]), package_type: 'npm' }],
  ]) assert.throws(() => validateVersions(versions));
});

test('inventory changes abort before deleting a version that could have been retagged', async () => {
  const fixture = clientFixture([version(1, [sha])]);
  let reads = 0;
  await assert.rejects(retain({
    ...fixture, apply: true,
    listVersions: async () => ++reads === 1 ? [version(1, [sha])] : [version(1, [sha, 'latest'])],
  }), /changed during preflight/);
  assert.deepEqual(fixture.deleted, []);
});

test('rechecks the full inventory between deletes and stops on concurrent publication', async () => {
  const fixture = clientFixture([version(1, [sha]), version(2, [sha])]);
  let reads = 0;
  await assert.rejects(retain({
    ...fixture, apply: true,
    listVersions: async () => {
      const inventory = await fixture.listVersions();
      return ++reads >= 4 ? [...inventory, version(3, ['nightly'])] : inventory;
    },
  }), /changed during cleanup/);
  assert.deepEqual(fixture.deleted, [1]);
});

const response = (body, headers = {}, status = 200) => new Response(status === 204 ? null : JSON.stringify(body), { status, headers });

test('REST uses user/org package endpoints, exhaustive pagination, and correct DELETE contract', async () => {
  for (const type of ['User', 'Organization']) {
    const calls = [];
    const versions = Array.from({ length: 100 }, (_, i) => version(i + 1, [sha]));
    const prefix = type === 'User' ? 'users' : 'orgs';
    const client = createClient({ owner: 'test-owner', actor: 'test', token: 'fixture-token', fetchImpl: async (url, options) => {
      calls.push({ url, options });
      assert.equal(options.redirect, 'error');
      assert.equal(options.headers['X-GitHub-Api-Version'], '2022-11-28');
      if (url.endsWith('/users/test-owner')) return response({ type });
      assert.ok(url.includes(`/${prefix}/test-owner/packages/container/powerbgp/versions`));
      if (options.method === 'DELETE') return response(null, {}, 204);
      if (url.endsWith('page=1')) return response(versions);
      assert.ok(url.endsWith('page=2'));
      return response([version(101, [sha])]);
    } });
    assert.equal((await client.listVersions()).length, 101);
    await client.deleteVersion(1);
    assert.equal(calls.at(-1).options.method, 'DELETE');
    assert.ok(calls.at(-1).url.endsWith('/versions/1'));
  }
});

test('malformed pagination, duplicate pages, wrong owner and API errors fail closed', async () => {
  for (const scenario of ['link', 'duplicate', 'owner', 'denied', 'shape']) {
    const client = createClient({ owner: 'test', actor: 'test', token: 'fixture', fetchImpl: async url => {
      if (url.endsWith('/users/test')) return response({ type: scenario === 'owner' ? 'Bot' : 'User' });
      if (scenario === 'denied') return response({}, {}, 403);
      if (scenario === 'shape') return response({ error: 'truncated' });
      if (scenario === 'link') return response([version(1, [sha])], { link: '<https://example.com/page=2>; rel="next"' });
      if (url.endsWith('page=1')) return response(Array.from({ length: 100 }, (_, i) => version(i + 1, [sha])));
      return response([version(1, [sha])]);
    } });
    await assert.rejects(client.listVersions());
  }
});

test('registry token is scoped to the package; downloaded manifest digest is verified', async () => {
  const bytes = JSON.stringify(image);
  const name = `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
  let tokenRequests = 0;
  const client = createClient({ owner: 'Test', actor: 'test', token: 'fixture', fetchImpl: async (url, options) => {
    if (url.startsWith('https://ghcr.io/token?')) {
      tokenRequests++;
      assert.ok(url.includes('scope=repository:test/powerbgp:pull'));
      assert.ok(options.headers.Authorization.startsWith('Basic '));
      return response({ token: 'registry-fixture' });
    }
    assert.equal(options.headers.Authorization, 'Bearer registry-fixture');
    assert.ok(url.startsWith('https://ghcr.io/v2/test/powerbgp/manifests/'));
    return new Response(bytes);
  } });
  assert.deepEqual(await client.readManifest(name), image);
  assert.deepEqual(await client.readManifest(name), image);
  assert.equal(tokenRequests, 1);
  await assert.rejects(client.readManifest(digest(1)), /digest mismatch/);
});
