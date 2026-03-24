# Taddy API Reference

## GraphQL Endpoint

- **URL**: `https://api.taddy.org/graphql`
- **Method**: POST
- **Auth headers**: `X-USER-ID` (numeric), `X-API-KEY` (string), `User-Agent` required

## Queries

### searchForTerm
Full-text search across podcasts and episodes.

| Argument | Type | Notes |
|----------|------|-------|
| term | String! | Search term, prefix with `-` to exclude |
| page | Int | 1-20, default 1 |
| limitPerPage | Int | 1-25, default 10 |
| filterForTypes | [SearchContentType] | PODCASTSERIES, PODCASTEPISODE |
| filterForCountries | [Country] | |
| filterForLanguages | [Language] | |
| filterForGenres | [Genre] | |
| filterForSeriesUuids | [ID] | Search within specific series |
| filterForNotInSeriesUuids | [ID] | Exclude specific series |
| filterForPodcastContentType | [PodcastContentType] | AUDIO, VIDEO |
| filterForPublishedAfter | Int | Epoch seconds |
| filterForPublishedBefore | Int | Epoch seconds |
| filterForHasTranscript | Boolean | Episodes only |
| filterForHasChapters | Boolean | Episodes only |
| filterForDurationLessThan | Int | Seconds, episodes only |
| filterForDurationGreaterThan | Int | Seconds, episodes only |
| sortBy | SearchSortOrder | EXACTNESS (default), POPULARITY |
| matchBy | SearchMatchType | MOST_TERMS (default), ALL_TERMS, FREQUENCY |

Returns: searchId, podcastSeries[], podcastEpisodes[]

### getPodcastSeries
Get podcast by uuid, itunesId, rssUrl, or name.

### getMultiplePodcastSeries
Get up to 25 podcasts by uuids array.

### getPodcastEpisode
Get episode by uuid.

### getTopChartsByCountry
| Argument | Type | Notes |
|----------|------|-------|
| taddyType | TaddyType! | PODCASTSERIES or PODCASTEPISODE |
| country | Country! | |
| source | TopChartsSource | Default: APPLE_PODCASTS |
| page | Int | 1-20 |
| limitPerPage | Int | 1-25 |

### getTopChartsByGenres
Same as above but with `genres: [Genre!]` instead of country.

## Types

### PodcastSeries
uuid, name, description, imageUrl, itunesId, datePublished, language, genres, authorName, websiteUrl, rssUrl, totalEpisodesCount, popularityRank, seriesType, contentType, isExplicitContent, isCompleted, copyright, hash, childrenHash, itunesInfo, persons, episodes(sortOrder, page, limitPerPage, searchTerm)

### PodcastEpisode
uuid, name, description, imageUrl, datePublished, guid, subtitle, audioUrl, videoUrl, fileLength, fileType, duration, episodeType, seasonNumber, episodeNumber, websiteUrl, isExplicitContent, isRemoved, taddyTranscribeStatus, transcript, podcastSeries

### iTunesInfo
uuid, subtitle, summary, baseArtworkUrl, baseArtworkUrlOf(size), publisherId, publisherName, country

## Genre Enums
PODCASTSERIES_TECHNOLOGY, PODCASTSERIES_BUSINESS, PODCASTSERIES_SCIENCE, PODCASTSERIES_NEWS, PODCASTSERIES_COMEDY, PODCASTSERIES_TRUE_CRIME, PODCASTSERIES_HEALTH_AND_FITNESS, PODCASTSERIES_ARTS, PODCASTSERIES_EDUCATION, PODCASTSERIES_SOCIETY_AND_CULTURE, PODCASTSERIES_SPORTS, PODCASTSERIES_HISTORY, PODCASTSERIES_MUSIC, PODCASTSERIES_TV_AND_FILM, PODCASTSERIES_GOVERNMENT, PODCASTSERIES_KIDS_AND_FAMILY, PODCASTSERIES_LEISURE, PODCASTSERIES_FICTION, PODCASTSERIES_RELIGION_AND_SPIRITUALITY

## Country Enums
UNITED_STATES_OF_AMERICA, UNITED_KINGDOM, CANADA, AUSTRALIA, GERMANY, FRANCE, JAPAN, INDIA, BRAZIL, MEXICO, SOUTH_KOREA, SPAIN, ITALY, NETHERLANDS, SWEDEN, NORWAY, DENMARK, FINLAND
