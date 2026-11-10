import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';

const digestPattern = /^sha256:[0-9a-f]{64}$/;
const mediaTypes = [
  'application/vnd.oci.image.index.v1+json',
  'application/vnd.oci.image.manifest.v1+json',
  'application/vnd.docker.distribution.manifest.list.v2+json',
  'application/vnd.docker.distribution.manifest.v2+json',
];

function timestamp(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/.test(value) || !Number.isFinite(Date.parse(value))) {
    throw new Error('Missing or invalid version timestamp');
  }
  return Date.parse(value);
}

export function validateVersions(versions) {
  if (!Array.isArray(versions)) throw new Error('Incomplete version inventory');
  const ids = new Set();
  const digests = new Set();
  for (const version of versions) {
    if (!Number.isSafeInteger(version.id) || version.id <= 0 || ids.has(version.id) ||
        !digestPattern.test(version.name) || digests.has(version.name) ||
        version.package_type !== 'container' || !Array.isArray(version.metadata?.container?.tags) ||
        version.metadata.container.tags.some(tag => typeof tag !== 'string' || !tag.length)) {
      throw new Error('Invalid or duplicate container version');
    }
    timestamp(version.created_at);
    timestamp(version.updated_at);
    ids.add(version.id);
    digests.add(version.name);
  }
  return versions;
}

function temporaryTag(tag, cutoff) {
  if (/^sha-[0-9a-f]{7,40}$/.test(tag)) return true;
  const match = /^date-(\d{4})(\d{2})(\d{2})$/.exec(tag);
  if (!match) return false;
  const iso = `${match[1]}-${match[2]}-${match[3]}T00:00:00.000Z`;
  const date = new Date(iso);
  return Number.isFinite(date.getTime()) && date.toISOString() === iso && date.getTime() < cutoff;
}

export function selectCandidates(versions, referenced, now = new Date()) {
  validateVersions(versions);
  if (!Number.isFinite(now.getTime())) throw new Error('Invalid retention clock');
  const cutoff = now.getTime() - 30 * 24 * 60 * 60 * 1000;
  return versions.filter(version => {
    const tags = version.metadata.container.tags;
    return tags.length > 0 && tags.every(tag => temporaryTag(tag, cutoff)) &&
      timestamp(version.created_at) < cutoff && timestamp(version.updated_at) < cutoff &&
      !referenced.has(version.name);
  });
}

export async function collectReferences(versions, readManifest) {
  validateVersions(versions);
  const queue = versions.map(version => version.name);
  const visited = new Set();
  const referenced = new Set();
  for (let i = 0; i < queue.length; i++) {
    const digest = queue[i];
    if (visited.has(digest)) continue;
    visited.add(digest);
    const manifest = await readManifest(digest);
    if (manifest?.schemaVersion !== 2 || !mediaTypes.includes(manifest.mediaType)) {
      throw new Error(`Unsupported manifest: ${digest}`);
    }
    const isIndex = manifest.mediaType === mediaTypes[0] || manifest.mediaType === mediaTypes[2];
    if (isIndex && (!Array.isArray(manifest.manifests) || !manifest.manifests.length)) {
      throw new Error(`Incomplete manifest index: ${digest}`);
    }
    if (!isIndex && (!digestPattern.test(manifest.config?.digest) || !Array.isArray(manifest.layers) ||
        manifest.layers.some(layer => !digestPattern.test(layer?.digest)))) {
      throw new Error(`Incomplete image manifest: ${digest}`);
    }
    const children = isIndex ? [...manifest.manifests] : [];
    if (manifest.subject !== undefined) children.push(manifest.subject);
    for (const child of children) {
      if (!digestPattern.test(child?.digest) || !mediaTypes.includes(child.mediaType)) {
        throw new Error(`Invalid child manifest: ${digest}`);
      }
      referenced.add(child.digest);
      queue.push(child.digest);
    }
  }
  return referenced;
}

function snapshot(versions) {
  validateVersions(versions);
  return JSON.stringify(versions.map(version => ({
    id: version.id, name: version.name, created: version.created_at, updated: version.updated_at,
    tags: [...version.metadata.container.tags].sort(),
  })).sort((a, b) => a.id - b.id));
}

export async function retain({ listVersions, readManifest, deleteVersion, apply = false, now = new Date(), log = console.log }) {
  const versions = validateVersions(await listVersions());
  const references = await collectReferences(versions, readManifest);
  const candidates = selectCandidates(versions, references, now);
  let remaining = versions;
  // Complete preflight before the first DELETE; also detect publication or retagging between deletes.
  if (snapshot(await listVersions()) !== snapshot(remaining)) throw new Error('Package changed during preflight');
  for (const version of candidates) {
    log(`${apply ? 'Delete' : 'Would delete'} ${version.id}: ${version.metadata.container.tags.join(', ')}`);
    if (apply) {
      if (snapshot(await listVersions()) !== snapshot(remaining)) throw new Error('Package changed during cleanup');
      await deleteVersion(version.id);
      remaining = remaining.filter(item => item.id !== version.id);
    }
  }
  log(`${apply ? 'Deleted' : 'Dry run:'} ${candidates.length} old tagged version(s); untagged and referenced manifests preserved.`);
  return candidates;
}

export function createClient({ owner, actor, token, fetchImpl = fetch }) {
  if (!/^[a-zA-Z0-9-]+$/.test(owner ?? '') || !actor || !token) throw new Error('Owner, actor and token are required');
  const api = 'https://api.github.com';
  const registry = `https://ghcr.io/v2/${owner.toLowerCase()}/powerbgp`;
  let packagePath;
  let registryToken;
  async function request(url, headers, method = 'GET') {
    const response = await fetchImpl(url, { method, headers, redirect: 'error', signal: AbortSignal.timeout(30000) });
    if (!response.ok) throw new Error(`${method} ${new URL(url).pathname} failed: ${response.status}`);
    return response;
  }
  const apiHeaders = {
    Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };
  async function initialize() {
    if (packagePath) return;
    const account = await (await request(`${api}/users/${owner}`, apiHeaders)).json();
    if (!['User', 'Organization'].includes(account.type)) throw new Error('Unknown package owner type');
    packagePath = `${account.type === 'Organization' ? 'orgs' : 'users'}/${owner}/packages/container/powerbgp/versions`;
  }
  return {
    async listVersions() {
      await initialize();
      const versions = [];
      let page = 1;
      while (true) {
        if (page > 1000) throw new Error('Version inventory exceeded safety limit');
        const response = await request(`${api}/${packagePath}?per_page=100&page=${page}`, apiHeaders);
        const batch = await response.json();
        if (!Array.isArray(batch) || batch.length > 100) throw new Error('Invalid version page');
        versions.push(...batch);
        const link = response.headers.get('link');
        if (link && link.split(',').some(part => !/^\s*<https:\/\/api\.github\.com\/[^>]+>;\s*rel="(?:next|prev|first|last)"\s*$/.test(part))) {
          throw new Error('Malformed pagination header');
        }
        const hasNext = link?.includes('rel="next"');
        if (hasNext) {
          const next = /<([^>]+)>;\s*rel="next"/.exec(link)?.[1];
          const expected = new URL(`${api}/${packagePath}?per_page=100&page=${page + 1}`);
          const actual = next && new URL(next);
          if (!actual || actual.origin !== expected.origin || actual.pathname !== expected.pathname ||
              actual.searchParams.get('page') !== String(page + 1) || actual.searchParams.get('per_page') !== '100' || !batch.length) {
            throw new Error('Invalid pagination link');
          }
        } else if (batch.length < 100) {
          break;
        }
        page++;
      }
      return validateVersions(versions);
    },
    async readManifest(digest) {
      if (!digestPattern.test(digest)) throw new Error('Invalid manifest digest');
      if (!registryToken) {
        const url = `https://ghcr.io/token?service=ghcr.io&scope=repository:${owner.toLowerCase()}/powerbgp:pull`;
        const result = await (await request(url, { Authorization: `Basic ${Buffer.from(`${actor}:${token}`).toString('base64')}` })).json();
        registryToken = result.token;
        if (typeof registryToken !== 'string' || !registryToken) throw new Error('Missing registry pull token');
      }
      const response = await request(`${registry}/manifests/${digest}`, {
        Authorization: `Bearer ${registryToken}`, Accept: mediaTypes.join(', '),
      });
      const bytes = Buffer.from(await response.arrayBuffer());
      if (`sha256:${createHash('sha256').update(bytes).digest('hex')}` !== digest) throw new Error('Manifest digest mismatch');
      return JSON.parse(bytes.toString('utf8'));
    },
    async deleteVersion(id) {
      await initialize();
      if (!Number.isSafeInteger(id) || id <= 0) throw new Error('Invalid version id');
      const response = await request(`${api}/${packagePath}/${id}`, apiHeaders, 'DELETE');
      if (response.status !== 204) throw new Error('Unexpected delete response');
    },
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    if (process.argv.slice(2).some(arg => !['--apply', '--dry-run'].includes(arg)) ||
        (process.argv.includes('--apply') && process.argv.includes('--dry-run'))) throw new Error('Use --apply or --dry-run');
    await retain({ ...createClient({ owner: process.env.GITHUB_REPOSITORY_OWNER, actor: process.env.GITHUB_ACTOR, token: process.env.GH_TOKEN }), apply: process.argv.includes('--apply') });
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
