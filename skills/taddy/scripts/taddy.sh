#!/usr/bin/env bash
set -euo pipefail

TADDY_USER_ID="${TADDY_USER_ID:?Set TADDY_USER_ID}"
TADDY_API_KEY="${TADDY_API_KEY:?Set TADDY_API_KEY}"

taddy() {
  python3 - "$@" <<'PYEOF'
import sys, json, urllib.request

endpoint = "https://api.taddy.org/graphql"
user_id = sys.argv[1]
api_key = sys.argv[2]
query = sys.argv[3]
variables = json.loads(sys.argv[4]) if len(sys.argv) > 4 else {}

body = json.dumps({"query": query, "variables": variables}).encode()
req = urllib.request.Request(endpoint, data=body, headers={
    "Content-Type": "application/json",
    "X-USER-ID": user_id,
    "X-API-KEY": api_key,
    "User-Agent": "Axion/1.0",
})
resp = urllib.request.urlopen(req).read().decode()
parsed = json.loads(resp)
print(json.dumps(parsed, indent=2))
PYEOF
}

gql() {
  taddy "$TADDY_USER_ID" "$TADDY_API_KEY" "$@"
}

cmd="${1:?Usage: taddy.sh <command> [args...]}"
shift

case "$cmd" in
  search)
    term="${1:?Usage: taddy.sh search <term> [limit]}"
    limit="${2:-10}"
    gql '{ searchForTerm(term: "'"$term"'", limitPerPage: '"$limit"', filterForTypes: [PODCASTSERIES]) { searchId podcastSeries { uuid name description imageUrl itunesId genres totalEpisodesCount } } }'
    ;;

  search-episodes)
    term="${1:?Usage: taddy.sh search-episodes <term> [limit]}"
    limit="${2:-10}"
    gql '{ searchForTerm(term: "'"$term"'", limitPerPage: '"$limit"', filterForTypes: [PODCASTEPISODE]) { searchId podcastEpisodes { uuid name description audioUrl datePublished duration podcastSeries { uuid name } } } }'
    ;;

  podcast)
    id="${1:?Usage: taddy.sh podcast <uuid|name>}"
    if [[ "$id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
      gql '{ getPodcastSeries(uuid: "'"$id"'") { uuid name description imageUrl itunesId datePublished language genres authorName websiteUrl rssUrl totalEpisodesCount seriesType contentType itunesInfo { uuid publisherName baseArtworkUrlOf(size: 640) } episodes(limitPerPage: 5, sortOrder: LATEST) { uuid name datePublished audioUrl duration } } }'
    else
      gql '{ getPodcastSeries(name: "'"$id"'") { uuid name description imageUrl itunesId datePublished language genres authorName websiteUrl rssUrl totalEpisodesCount seriesType contentType itunesInfo { uuid publisherName baseArtworkUrlOf(size: 640) } episodes(limitPerPage: 5, sortOrder: LATEST) { uuid name datePublished audioUrl duration } } }'
    fi
    ;;

  episode)
    uuid="${1:?Usage: taddy.sh episode <uuid>}"
    gql '{ getPodcastEpisode(uuid: "'"$uuid"'") { uuid name description imageUrl datePublished audioUrl videoUrl duration fileLength fileType episodeType seasonNumber episodeNumber websiteUrl isExplicitContent podcastSeries { uuid name itunesId } } }'
    ;;

  episodes)
    podcast_uuid="${1:?Usage: taddy.sh episodes <podcast-uuid> [limit]}"
    limit="${2:-10}"
    gql '{ getPodcastSeries(uuid: "'"$podcast_uuid"'") { uuid name totalEpisodesCount episodes(limitPerPage: '"$limit"', sortOrder: LATEST) { uuid name datePublished audioUrl duration description } } }'
    ;;

  transcript)
    uuid="${1:?Usage: taddy.sh transcript <episode-uuid>}"
    gql '{ getPodcastEpisode(uuid: "'"$uuid"'") { uuid name taddyTranscribeStatus transcript podcastSeries { uuid name } } }'
    ;;

  top-charts)
    country="${1:-UNITED_STATES_OF_AMERICA}"
    limit="${2:-25}"
    gql '{ getTopChartsByCountry(taddyType: PODCASTSERIES, country: '"$country"', limitPerPage: '"$limit"') { topChartsId podcastSeries { uuid name description imageUrl itunesId genres } } }'
    ;;

  top-genre)
    genre="${1:?Usage: taddy.sh top-genre <genre> [limit]}"
    limit="${2:-25}"
    gql '{ getTopChartsByGenres(taddyType: PODCASTSERIES, genres: ['"$genre"'], limitPerPage: '"$limit"') { topChartsId podcastSeries { uuid name description imageUrl itunesId genres } } }'
    ;;

  multi)
    uuids_csv="${1:?Usage: taddy.sh multi <uuid1,uuid2,...>}"
    uuids_quoted=$(echo "$uuids_csv" | sed 's/,/","/g' | sed 's/^/"/;s/$/"/')
    gql '{ getMultiplePodcastSeries(uuids: ['"$uuids_quoted"']) { uuid name description imageUrl itunesId genres totalEpisodesCount } }'
    ;;

  *)
    echo "Unknown command: $cmd"
    echo "Commands: search, search-episodes, podcast, episode, episodes, transcript, top-charts, top-genre, multi"
    exit 1
    ;;
esac
