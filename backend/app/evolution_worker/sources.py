import hashlib
import ipaddress
import re
import socket
import asyncio
from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from difflib import SequenceMatcher
from html.parser import HTMLParser
from urllib.parse import parse_qsl, urlencode, urljoin, urlsplit, urlunsplit

import httpx

from app.evolution_worker.models import SourceDocument


TRUSTED_HOSTS = {
    'fia.com': (1, 'fia_official'),
    'formula1.com': (2, 'formula1_official'),
    'mercedesamgf1.com': (3, 'team_official'),
    'redbullracing.com': (3, 'team_official'),
    'ferrari.com': (3, 'team_official'),
    'mclaren.com': (3, 'team_official'),
    'astonmartinf1.com': (3, 'team_official'),
    'alpinef1.com': (3, 'team_official'),
    'williamsf1.com': (3, 'team_official'),
    'racingbulls.com': (3, 'team_official'),
    'stakef1team.com': (3, 'team_official'),
    'haasf1team.com': (3, 'team_official'),
    'audi.com': (3, 'team_official'),
    'cadillacf1team.com': (3, 'team_official'),
    'motorsport.com': (4, 'technical_media'),
    'autosport.com': (4, 'technical_media'),
    'the-race.com': (4, 'technical_media'),
    'racefans.net': (4, 'technical_media'),
}
TEAM_DOMAINS = {
    'mclaren': ('mclaren.com',), 'ferrari': ('ferrari.com',),
    'mercedes': ('mercedesamgf1.com',), 'red_bull': ('redbullracing.com',),
    'alpine': ('alpinef1.com',), 'williams': ('williamsf1.com',),
    'haas': ('haasf1team.com',), 'cadillac': ('cadillacf1team.com',),
    'aston_martin': ('astonmartinf1.com',), 'audi': ('audi.com',),
    'racing_bulls': ('racingbulls.com',),
}
USER_AGENT = 'GrandPrixReminder-Evolution/0.1 (+evidence-only collector)'
MAX_BODY_BYTES = 2_000_000
MAX_DOCUMENT_CHARS = 40_000
MAX_SOURCE_URLS = 24
TRACKING_QUERY_KEYS = {'fbclid', 'gclid', 'mc_cid', 'mc_eid', 'ref', 'source'}


def canonical_url(url: str) -> str:
    parsed = urlsplit(url)
    query = urlencode([
        (key, value) for key, value in parse_qsl(parsed.query, keep_blank_values=True)
        if not key.casefold().startswith('utm_') and key.casefold() not in TRACKING_QUERY_KEYS
    ])
    path = parsed.path or '/'
    if path != '/':
        path = path.rstrip('/')
    return urlunsplit((parsed.scheme.casefold(), parsed.netloc.casefold(), path, query, ''))


class _TextExtractor(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.skip = 0
        self.parts: list[str] = []
        self.title_parts: list[str] = []
        self.in_title = False

    def handle_starttag(self, tag, attrs):
        if tag in {'script', 'style', 'svg', 'nav', 'noscript'}:
            self.skip += 1
        if tag == 'title':
            self.in_title = True
        if not self.skip and tag in {'p', 'article', 'section', 'h1', 'h2', 'h3', 'li', 'br'}:
            self.parts.append('\n')

    def handle_endtag(self, tag):
        if tag in {'script', 'style', 'svg', 'nav', 'noscript'} and self.skip:
            self.skip -= 1
        if tag == 'title':
            self.in_title = False

    def handle_data(self, data):
        if self.skip:
            return
        self.parts.append(data)
        if self.in_title:
            self.title_parts.append(data)


def clean_html(html: str) -> tuple[str, str]:
    parser = _TextExtractor()
    parser.feed(html)
    title = re.sub(r'\s+', ' ', ' '.join(parser.title_parts)).strip() or 'Untitled source'
    lines = [re.sub(r'\s+', ' ', line).strip() for line in ''.join(parser.parts).splitlines()]
    cleaned = '\n'.join(line for line in lines if line)[:MAX_DOCUMENT_CHARS]
    return title, cleaned


def published_at_from_html(html: str) -> datetime | None:
    match = re.search(
        r'<meta[^>]+(?:property|name)=["\'](?:article:published_time|date|publishdate)["\'][^>]+content=["\']([^"\']+)',
        html, re.IGNORECASE,
    ) or re.search(r'["\']datePublished["\']\s*:\s*["\']([^"\']+)', html, re.IGNORECASE)
    if not match:
        return None
    try:
        value = datetime.fromisoformat(match.group(1).replace('Z', '+00:00'))
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def publication_phase(published_at: datetime | None, race_start: datetime | None,
                      race_end: datetime | None) -> str:
    if not published_at or not race_start or not race_end:
        return 'unknown'
    if published_at < race_start:
        return 'pre_race'
    if published_at < race_end:
        return 'weekend'
    return 'post_race'


def eligible_race_day_report(document: SourceDocument, race_name: str,
                             season: int, race_start: datetime | None,
                             aliases: tuple[str, ...] = ()) -> bool:
    """Select factual race reports or team quotes, never incidental/promotional pages."""
    title = document.title.casefold()
    url = str(document.url).casefold()
    report = ('race report' in title and 'grand prix' in title) or (
        document.source_type == 'formula1_official' and 'what the teams said' in title
        and 'race day' in title)
    places = (race_name.split()[0], *aliases)
    return (document.source_type in {'formula1_official', 'team_official'}
            and str(season) in f'{title} {url}'
            and any(place.casefold() in f'{title} {url}' for place in places if len(place) >= 4)
            and report and document.published_at is not None and race_start is not None
            and document.published_at >= race_start)


def _host_policy(host: str) -> tuple[int, str] | None:
    host = host.rstrip('.').lower()
    for allowed, policy in TRUSTED_HOSTS.items():
        if host == allowed or host.endswith(f'.{allowed}'):
            return policy
    return None


def validate_public_url(url: str, resolver=socket.getaddrinfo) -> tuple[str, int, str]:
    parsed = urlsplit(url)
    if parsed.scheme not in {'http', 'https'} or not parsed.hostname or parsed.username:
        raise ValueError('Source URL must be an unauthenticated HTTP(S) URL')
    policy = _host_policy(parsed.hostname)
    if policy is None:
        raise ValueError(f'Untrusted source host: {parsed.hostname}')
    try:
        addresses = resolver(parsed.hostname, parsed.port or (443 if parsed.scheme == 'https' else 80))
    except OSError as exc:
        raise ValueError(f'Unable to resolve trusted source host: {parsed.hostname}') from exc
    for address in {row[4][0] for row in addresses}:
        ip = ipaddress.ip_address(address)
        if not ip.is_global:
            raise ValueError(f'Source host resolved to a non-public address: {parsed.hostname}')
    query = urlencode([
        (key, value) for key, value in parse_qsl(parsed.query, keep_blank_values=True)
        if not key.casefold().startswith('utm_') and key.casefold() not in TRACKING_QUERY_KEYS
    ])
    # Preserve the path exactly for HTTP redirects; canonical_url is applied only
    # after the final response so identity normalization cannot alter navigation.
    normalized = urlunsplit((parsed.scheme.casefold(), parsed.netloc.casefold(),
                             parsed.path or '/', query, ''))
    return normalized, *policy


def deduplicate(documents: list[SourceDocument]) -> tuple[list[SourceDocument], int]:
    accepted: list[SourceDocument] = []
    urls: set[str] = set()
    hashes: set[str] = set()
    skipped = 0
    for document in documents:
        url = str(document.url)
        compact = re.sub(r'\W+', '', document.cleaned_text.casefold())
        if url in urls or document.content_hash in hashes or any(
            SequenceMatcher(None, compact, re.sub(r'\W+', '', item.cleaned_text.casefold())).ratio() >= .94
            for item in accepted
        ):
            skipped += 1
            continue
        urls.add(url)
        hashes.add(document.content_hash)
        accepted.append(document)
    return accepted, skipped


@dataclass
class CollectionResult:
    documents: list[SourceDocument]
    failures: list[str]
    duplicates_skipped: int = 0


class EvolutionSourceProvider(ABC):
    @abstractmethod
    async def collect(self, race_id: str, urls: list[str]) -> CollectionResult:
        raise NotImplementedError


class TrustedUrlProvider(EvolutionSourceProvider):
    """Fetch only explicitly supplied URLs from the fixed trusted-domain list."""

    def __init__(self, client: httpx.AsyncClient | None = None, resolver=socket.getaddrinfo):
        self.client = client
        self.resolver = resolver

    async def _fetch(self, race_id: str, url: str, client: httpx.AsyncClient) -> SourceDocument:
        current, tier, source_type = validate_public_url(url, self.resolver)
        for _ in range(6):
            response = None
            for attempt in range(2):
                response = await client.get(current, headers={'User-Agent': USER_AGENT}, follow_redirects=False)
                if response.status_code not in {429, 500, 502, 503, 504} or attempt == 1:
                    break
                await asyncio.sleep(1)
            assert response is not None
            if response.is_redirect:
                location = response.headers.get('location')
                if not location:
                    raise ValueError('Source returned an empty redirect')
                current, tier, source_type = validate_public_url(urljoin(current, location), self.resolver)
                continue
            response.raise_for_status()
            body = response.content
            if len(body) > MAX_BODY_BYTES:
                raise ValueError('Source body exceeds the 2 MB limit')
            content_type = response.headers.get('content-type', '')
            if 'html' not in content_type and not content_type.startswith('text/'):
                raise ValueError('First provider supports HTML/text sources only')
            raw = response.text
            title, cleaned = clean_html(raw)
            if len(cleaned) < 80:
                raise ValueError('Source contains too little readable text')
            digest = hashlib.sha256(cleaned.encode('utf-8')).hexdigest()
            # A source is its canonical URL; the content hash is its revision.
            identity_url = canonical_url(current)
            source_id = f'src_{hashlib.sha256(identity_url.encode()).hexdigest()[:20]}'
            return SourceDocument(
                source_id=source_id, race_id=race_id,
                publisher=urlsplit(current).hostname or 'unknown', source_type=source_type,
                source_tier=tier, title=title, url=identity_url,
                published_at=published_at_from_html(raw), fetched_at=datetime.now(timezone.utc), raw_text=raw[:MAX_DOCUMENT_CHARS],
                cleaned_text=cleaned, content_hash=digest,
            )
        raise ValueError('Source exceeded the redirect limit')

    async def collect(self, race_id: str, urls: list[str]) -> CollectionResult:
        documents: list[SourceDocument] = []
        failures: list[str] = []
        owns_client = self.client is None
        client = self.client or httpx.AsyncClient(timeout=httpx.Timeout(20, connect=8))
        try:
            for url in list(dict.fromkeys(urls))[:MAX_SOURCE_URLS]:
                try:
                    documents.append(await self._fetch(race_id, url, client))
                except Exception as exc:
                    host = urlsplit(url).hostname or 'invalid-url'
                    failures.append(f'{host}: {type(exc).__name__}')
        finally:
            if owns_client:
                await client.aclose()
        unique, skipped = deduplicate(documents)
        return CollectionResult(unique, failures, skipped)


class TeamWebsiteProvider(TrustedUrlProvider):
    """One provider for configured official team domains; no search snippets."""
    def __init__(self, team_id: str, *args, **kwargs):
        super().__init__(*args, **kwargs)
        if team_id not in TEAM_DOMAINS:
            raise ValueError(f'Unsupported team website: {team_id}')
        self.team_id = team_id

    async def collect(self, race_id: str, urls: list[str]) -> CollectionResult:
        allowed = TEAM_DOMAINS[self.team_id]
        for url in urls:
            host = (urlsplit(url).hostname or '').lower()
            if not any(host == domain or host.endswith(f'.{domain}') for domain in allowed):
                raise ValueError(f'URL is not on the official {self.team_id} domain')
        result = await super().collect(race_id, urls)
        result.documents = [item.model_copy(update={'team_ids': [self.team_id]}) for item in result.documents]
        return result


class _LinkCollector(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.links: list[tuple[str, str]] = []
        self.href: str | None = None
        self.text: list[str] = []

    def handle_starttag(self, tag, attrs):
        if tag == 'a':
            self.href = dict(attrs).get('href')
            self.text = []

    def handle_data(self, data):
        if self.href:
            self.text.append(data)

    def handle_endtag(self, tag):
        if tag == 'a' and self.href:
            self.links.append((self.href, ' '.join(self.text)))
            self.href = None


class OfficialSourceDiscovery:
    """Find candidate pages only on Formula 1 and team-owned sites."""
    max_candidates = 24

    @staticmethod
    def _priority(url: str) -> int:
        path = urlsplit(url).path.casefold()
        if 'what-the-teams-said-race-day' in path or 'race-report' in path:
            return 0
        if any(term in path for term in ('upgrade', 'technical', 'tech-talk')):
            return 1
        if 'lowdown' in path or 'debrief' in path:
            return 2
        if 'preview' in path or 'quiz' in path or 'win-a-' in path:
            return 9
        return 3

    @staticmethod
    def _balanced(candidates: list[str], limit: int) -> list[str]:
        groups: dict[str, list[str]] = {}
        for url in dict.fromkeys(candidates):
            groups.setdefault(urlsplit(url).hostname or '', []).append(url)
        selected = []
        for index in range(max(map(len, groups.values()), default=0)):
            for urls in groups.values():
                if index < len(urls):
                    selected.append(urls[index])
                    if len(selected) == limit:
                        return selected
        return selected

    def __init__(self, client: httpx.AsyncClient | None = None, resolver=socket.getaddrinfo):
        self.client = client
        self.resolver = resolver

    @staticmethod
    def _keywords(race_name: str, circuit: str | None, country: str | None,
                  city: str | None) -> set[str]:
        values = (race_name, circuit or '', country or '', city or '')
        return {word for value in values for word in re.findall(r'[a-z0-9]{4,}', value.casefold())
                if word not in {'grand', 'prix', 'race', 'formula'}}

    @staticmethod
    def _is_relevant(document: SourceDocument, race_name: str, keywords: set[str], season: int) -> bool:
        text = f'{document.title}\n{document.cleaned_text}'.casefold()
        name = ' '.join(race_name.casefold().split())
        return str(season) in text and (name in text or sum(word in text for word in keywords) >= 2)

    @staticmethod
    def _usable_url(url: str) -> bool:
        path = urlsplit(url).path.casefold()
        return not any(term in path for term in (
            'quiz', 'predictions', 'in-pictures', 'weather-forecast',
            'win-a-', 'signed-tee', 'tickets', 'merchandise',
        ))

    @staticmethod
    def _candidate_matches(url: str, label: str, keywords: set[str], season: int) -> bool:
        haystack = f'{url} {label}'.casefold()
        years = set(re.findall(r'20\d{2}', haystack))
        return (not years or str(season) in years) and any(word in haystack for word in keywords)

    async def _page_links(self, url: str, client: httpx.AsyncClient) -> list[tuple[str, str]]:
        current, _, source_type = validate_public_url(url, self.resolver)
        if source_type not in {'formula1_official', 'team_official'}:
            return []
        response = await client.get(current, headers={'User-Agent': USER_AGENT}, follow_redirects=True)
        response.raise_for_status()
        if len(response.content) > MAX_BODY_BYTES:
            return []
        parser = _LinkCollector()
        parser.feed(response.text)
        return [(urljoin(str(response.url), href), text) for href, text in parser.links]

    async def _sitemaps(self, host: str, client: httpx.AsyncClient) -> list[str]:
        """Read a small official sitemap index; it is discovery metadata, never evidence."""
        try:
            robots, _, _ = validate_public_url(f'https://{host}/robots.txt', self.resolver)
            response = await client.get(robots, headers={'User-Agent': USER_AGENT}, follow_redirects=True)
            response.raise_for_status()
            return re.findall(r'(?im)^sitemap:\s*(https?://\S+)', response.text)[:3]
        except (httpx.HTTPError, ValueError):
            return []

    async def discover(self, *, race_id: str, race_name: str, circuit: str | None = None,
                       country: str | None = None, city: str | None = None,
                       race_start: datetime | None = None) -> list[str]:
        keywords = self._keywords(race_name, circuit, country, city)
        if not keywords:
            return []
        season = int(race_id.split('-', 1)[0])
        hosts = ('www.formula1.com', *(host for host, (_, kind) in TRUSTED_HOSTS.items()
                                      if kind == 'team_official'))
        seeds = ['https://www.formula1.com/en/latest/all.html'] + [f'https://{host}/' for host in hosts[1:]]
        owns_client = self.client is None
        client = self.client or httpx.AsyncClient(timeout=httpx.Timeout(20, connect=8))
        candidates: list[str] = []
        try:
            for seed in seeds:
                try:
                    links = await self._page_links(seed, client)
                except (httpx.HTTPError, ValueError):
                    links = []
                for url, label in links:
                    if self._usable_url(url) and self._candidate_matches(url, label, keywords, season):
                        candidates.append(url)
                host = urlsplit(seed).hostname
                if host:
                    for sitemap in await self._sitemaps(host, client):
                        try:
                            sitemap_url, _, source_type = validate_public_url(sitemap, self.resolver)
                            if source_type not in {'formula1_official', 'team_official'}:
                                continue
                            xml = await client.get(sitemap_url, headers={'User-Agent': USER_AGENT})
                            xml.raise_for_status()
                            if len(xml.content) > MAX_BODY_BYTES:
                                continue
                            if source_type == 'formula1_official':
                                index = next((url for url in re.findall(r'<loc>([^<]+)</loc>', xml.text)
                                              if url.endswith('/en/latest/article/sitemap.xml')), None)
                                if index:
                                    index_url, _, _ = validate_public_url(index, self.resolver)
                                    xml = await client.get(index_url, headers={'User-Agent': USER_AGENT})
                                    xml.raise_for_status()
                                    if len(xml.content) > MAX_BODY_BYTES:
                                        continue
                                    sitemap_url = index_url
                            locations = re.findall(r'<loc>([^<]+)</loc>', xml.text)
                            if sitemap_url.endswith('/en/latest/article/sitemap.xml'):
                                # Formula1.com exposes an index of 1000-article sitemaps.
                                # The latest eight cover current and recent-season reports.
                                for child in locations[-8:]:
                                    try:
                                        child_url, _, child_type = validate_public_url(child, self.resolver)
                                        if child_type != 'formula1_official':
                                            continue
                                        page = await client.get(child_url, headers={'User-Agent': USER_AGENT})
                                        page.raise_for_status()
                                        if len(page.content) <= MAX_BODY_BYTES:
                                            candidates.extend(url for url in re.findall(
                                                r'<loc>([^<]+)</loc>', page.text)
                                                if self._usable_url(url) and
                                                self._candidate_matches(url, '', keywords, season))
                                    except (httpx.HTTPError, ValueError):
                                        continue
                            else:
                                candidates.extend(url for url in locations
                                                  if self._usable_url(url) and
                                                  self._candidate_matches(url, '', keywords, season))
                        except (httpx.HTTPError, ValueError):
                            continue
            selected = self._balanced(sorted(candidates, key=self._priority), self.max_candidates)
            documents = await TrustedUrlProvider(client, self.resolver).collect(race_id, selected)
            return [str(item.url) for item in documents.documents
                    if self._is_relevant(item, race_name, keywords, season)
                    and (race_start is None or (item.published_at is not None
                         and race_start - timedelta(days=7) <= item.published_at
                         <= race_start + timedelta(days=7)))]
        finally:
            if owns_client:
                await client.aclose()
