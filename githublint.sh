#!/bin/bash -ue

declare -r ARG_MAX="$(getconf ARG_MAX)"
declare -r CURL_OPTS=${CURL_OPTS:--sfL}
declare -r GITHUB_API_ORIGIN=${GITHUB_API_ORIGIN:-https://api.github.com}
declare DEBUG=${DEBUG:-0}
declare XTRACE=${XTRACE:-0}
declare REPO_FILTER=${REPO_FILTER:-.}
declare REPORTER=${REPORTER:-tsv}
declare EXTENSIONS="${EXTENSIONS:-stats/commit_activity,teams,codeowners,branches}"
declare RC_FILE=${RC_FILE:-.githublintrc.json}

function log() {
  (
    set +x
    local level="$1"
    local color="$2"
    shift 2
    printf '\e[%sm[%s] ' "$color" "$level"
    if [ $# -ne 0 ]
    then
      printf "$@"
    else
      cat
    fi
    printf '\n\e[m'
  ) >&2
}

function warn() {
  log WARN 35 "$@"
}

function debug() {
  if [ $DEBUG -ne 0 ]
  then
    log DEBUG 37 "$@"
  fi
}

function info() {
  log INFO 36 "$@"
}

function usage() {
  echo "Usage: $0 [-d] [-x] [-h] [-c run-control] [-f filter] [-r tsv|json|json-seq] [-e extension[,extension]...] slug" >&2
}

while getopts "c:de:f:hr:x" opt
do
  case "$opt" in
    c) RC_FILE="$OPTARG" ;;
    d) DEBUG=1 ;;
    e) EXTENSIONS="$OPTARG" ;;
    f) REPO_FILTER="$OPTARG" ;;
    r) REPORTER="$OPTARG" ;;
    x) XTRACE=1 ;;
    h) usage ; exit 0 ;;
    ?) usage ; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

test $DEBUG -ne 0 -a -f "$RC_FILE" && {
  printf 'Run-Control file was found. '
  jq -jcM '.' "$RC_FILE"
} | debug

if [ $XTRACE -ne 0 ]
then
  set -x
  declare -p
  bash --version
  node --version
  curl --version
  jq --version
fi >&2

function finally () {
  debug 'command exited with status %d' $?
  rm -f .curlrc
}

trap finally EXIT

test $# -eq 1 || { usage ; exit 1; }

declare -r SLUG="$1"
declare -r ORG="$(echo "$SLUG" | grep '^orgs/' | sed -e 's/^orgs\///')"

curlrc="$(mktemp)"
test -e "$HOME/.curlrc" && cp "$HOME/.curlrc" "$curlrc"
cat >> "$curlrc" <<EOF
$CURL_OPTS
$(test $DEBUG -ne 0 && echo '-S')
-H "Accept: application/vnd.github.v3+json, application/vnd.github.luke-cage-preview+json" 
-u username:$GITHUB_TOKEN
EOF

parse_header_js="$(mktemp)"
cat > "$parse_header_js" <<'EOF'
#!/usr/bin/env node

const parseres = {
  link: value => {
    return value.split(',')
      .map(element => element.split(';').map(e => e.trim()))
      .map(([ref, ...params]) => {
        const href = new URL(ref.replace(/(^<|>$)/g, ''));
        href.toJSON = function (key) {
          this.searchParams.toJSON = function (key) {
            const o = {};
            for (const [key, value] of this) o[key] = value;
            return o;
          };
          const o = {};
          for (const key in this) if (!/^to(JSON|String)/.test(key)) o[key] = this[key];
          return o;
        };
        return {
          href,
          ...(
            params.map(param => {
              const [key, value] = param.split('=');
              return { key, value: value.replace(/(^"|"$)/g, '') };
            }).reduce((p, c) => { p[c.key] = c.value; return p; }, {})
          )
        };
      });
  }
};

(async () => {
  const buffers = [];
  for await (const chunk of process.stdin) buffers.push(chunk);
  const buffer = Buffer.concat(buffers);
  const text = buffer.toString();
  const lines = text.split(/\r?\n|\r/);
  const objects = lines
    .filter(line => line)
    .map(line => {
      const index = line.indexOf(':');
      if (index === -1) return line;
      const key = line.substring(0, index).toLowerCase();
      const value = line.substring(index + 1).trim();
      const parse = parseres[key] || (value => value);
      return { [key]: parse(value) };
    });
  console.log(JSON.stringify(objects));
})();
EOF

function parse_header() {
  node "$parse_header_js" "$@"
}

function request() {
  curl -K "$curlrc" "$@"
}

function list() {
  local url="$1"
  shift
  local num_of_pages
  num_of_pages=$(
    request -I "${url}" "$@" |
      parse_header |
      jq -r '
      map(select(.link?)) |
      map(.link | map(select(.rel == "last")) | map(.href.searchParams.page)) |
      flatten | first // empty
      '
  )
  params="$(if [ -n "${num_of_pages}" ]; then printf 'page=[1-%d]' "${num_of_pages}"; fi)"
  request "${url}?${params}" "$@"
}

function find_blob() {
  local repo=$1
  local ref=$2
  local path=$3
  local sha
  sha=$(request "${GITHUB_API_ORIGIN}/repos/$repo/git/${ref}" | jq -r '.object.sha')
  test "$sha" != 'null' &&
    request "${GITHUB_API_ORIGIN}/repos/$repo/git/trees/${sha}?recursive=1" |
      jq -c --arg path "$path" '.tree|map(select(.path|test($path)))'
}

function fetch_content() {
  local url=${1:-null}
  test "${url}" != 'null' && request "$url" | jq -r '.content | gsub("\\s"; "") | @base64d'
}

function parse_codeowners() {
  jq -sRc '
  split("(\\r?\\n|\\r)"; "") |
  map(select((test("^#") or . == "") | not)) |
  map(
    gsub("\\\\ "; "\\\b") |
    split("\\s+"; "") |
    map(gsub("[\\b]"; " ")) |
    { pattern: .[0], owners: .[1:] }
  )
  '
}

function fetch_codeowners() {
  local repo="$1"
  local ref="$2"
  local blobs
  blobs="$(find_blob "$repo" "$ref" '^(|docs/|\.github/)CODEOWNERS$')"
  jq -nc --argjson blobs "${blobs:-[]}" '$blobs|.[]' |
    while IFS= read -r blob
    do
      jq -nr --argjson blob "${blob:-null}" '$blob | [.path, .url] | @tsv' | {
        IFS=$'\t' read -r path url
        fetch_content "$url" | parse_codeowners | jq -c --arg path "$path" '{$path, entries: .}'
      }
    done | jq -sc
}

function fetch_branches() {
  local full_name="$1"
  list "${GITHUB_API_ORIGIN}/repos/$full_name/branches" |
    jq -c '.[]' |
    while IFS= read -r branch
    do
      values=($(jq -nr --argjson branch "$branch" '[$branch.name, $branch.protected, $branch.protection_url] | @tsv'))
      branch_name="${values[0]}"
      protected="${values[1]}"
      protection_url="${values[2]}"
      if [ "$protected" = "true" ]
      then
        request "$protection_url" | jq -c '{ protection: . }'
      else
        echo '{}'
      fi | jq -c --argjson branch "$branch" '$branch * .'
    done | jq -sc
}

function fetch_repository() {
  local repo="$1"
  local values
  values=($(echo "$repo" | jq -r '[.full_name,.default_branch]|@tsv'))
  local full_name=${values[0]}
  local default_branch=${values[1]}

  local commit_activity='{}'
  if echo "$EXTENSIONS" | grep -q '\bstats/commit_activity\b'
  then
    commit_activity=$(request "${GITHUB_API_ORIGIN}/repos/$full_name/stats/commit_activity" | jq -c)
    debug '%s commit_activity JSON size: %d' "$full_name" ${#commit_activity}
  fi

  local teams='[]'
  if echo "$EXTENSIONS" | grep -q '\bteams\b'
  then
    teams=$(list "${GITHUB_API_ORIGIN}/repos/$full_name/teams" | jq -c)
    debug '%s teams JSON size: %d' "$full_name" ${#teams}
  fi

  local codeowners='[]'
  if echo "$EXTENSIONS" | grep -q '\bcodeowners\b'
  then
    codeowners="$(fetch_codeowners "$full_name" "ref/heads/${default_branch}")"
    debug '%s codeowners JSON size: %d' "$full_name" ${#codeowners}
  fi

  local branches_dump
  branches_dump="$(mktemp)"
  echo '[]' > "$branches_dump"
  if echo "$EXTENSIONS" | grep -q '\bbranches\b'
  then
    fetch_branches "$full_name" > "$branches_dump"
    debug '%s branches JSON size: %d' "$full_name" "$(wc -c < "$branches_dump")"
  fi

  local repo_dump
  repo_dump="$(mktemp)"
  jq -cs 'add' \
    <(echo "$repo") \
    <(echo "${commit_activity:-null}" | jq -c '{stats:{commit_activity:.}}') \
    <(echo "${teams:-null}" | jq -c '{teams:.}') \
    <(echo "${codeowners:-null}" | jq -c '{codeowners:.}') \
    <(< "$branches_dump" jq -c '{branches:.}') | tee "$repo_dump"
  debug '%s repository JSON size: %d' "$full_name" "$(wc -c < "$repo_dump")"
  return 0
}

function new_json_sequence() {
  printf '\x1e'
  jq -sc 'add' "$@"
}

jq_lib=$(mktemp -d)
cat > "$jq_lib/githublint.jq" <<'EOF'
import ".githublintrc" as $rc;

def new_issue($descriptor):
  $descriptor + . | { signature, severity, confidence, message, location }
;

def run_control($key):
  $rc::rc | first | .[$key]
;

def analyze(process; default_configure; $descriptor):
  .resources.repositories | first |
  . as $repository |
  (run_control($descriptor.signature)) // default_configure |
  .patterns + [] | map(select(.filter as $filter | $repository.name | test($filter))) |
  map({ $repository, pattern: . } | process | new_issue($descriptor)) | .[]
;
EOF
if [ -f "$RC_FILE" ]
then
  cat < "$RC_FILE"
else
  echo '{}'
fi > "$jq_lib/.githublintrc.json"

function new_issue() {
  local signature="${FUNCNAME[1]}"

  local filter='
    import "githublint" as lint;

    $ARGS.positional |
    {
      message: .[0],
      location: { url: .[1] },
      severity: .[3],
      confidence: .[4]
    } | to_entries | map(select(.value != null)) | from_entries |
    lint::new_issue($descriptor)
  '
  jq -nc -L"$jq_lib" \
    --argfile descriptor <(eval "$signature" describe) \
    --args \
    "$filter" "$@"
}

function describe_rule() {
  local filter='
    $ARGS.positional |
    {
      $signature,
      name: .[0],
      description: .[1],
      severity: (.[2] // "Low"),
      confidence: (.[3] // "Low"),
      help: .[4],
      tags: (.[5] // "[]" | fromjson)
    }
  '
  jq -nc --arg signature "${FUNCNAME[1]}" --args "$filter" "$@"
}

# Repository Rules

function codeowners_file_exists_repo_rule() {
  test "${1:-}" = "describe" && {
    describe_rule "CODEOWNERS file exists"
    return
  }

  local filter='
    import "githublint" as lint;

    def default_configure:
      {
        patterns: [
          {
            filter: ".*"
          }
        ]
      }
    ;

    def analyze:
      .repository |
      if .codeowners | length > 0 then
        empty
      else
        { message: "CODEOWNERS file does not exist on default branch.", location: { url } }
      end
    ;

    lint::analyze(analyze; default_configure; $descriptor)
  '
  ! jq -ec -L"$jq_lib" \
    --argfile descriptor <(eval "$FUNCNAME" describe) \
    "$filter"
}

function readme_file_exists_repo_rule() {
  test "${1:-}" = "describe" && {
    describe_rule "README file exists"
    return
  }

  local url
  url="$(jq -r '.resources.repositories | first | .url')"
  request -I "${url}/readme" >/dev/null ||
    { new_issue "README file does not exist on default branch." "$url" && return 1; }
}

function protect_branches_repo_rule() {
  test "${1:-}" = "describe" && {
    describe_rule "Protect branches"
    return
  }

  local filter='
    import "githublint" as lint;

    def default_configure:
      {
        patterns: [
          {
            filter: ".*",
            branches: [.default_branch]
          }
        ]
      }
    ;

    def analyze:
      .pattern as $pattern |
      .repository |
      { location: { url } } as $issue |
      ($pattern.branches // []) as $branches |
      .branches | 
      map(select(.name as $name | $branches | any(. == $name))) |
      map(
        if .protected then
          empty
        else
          $issue + { message: "\(.name) branch is not protected." }
        end
      ) | .[]
    ;

    lint::analyze(analyze; default_configure; $descriptor)
  '
  ! jq -ec -L"$jq_lib" \
    --argfile descriptor <(eval "$FUNCNAME" describe) \
    "$filter"
}

function manage_team_access_repo_rule() {
  test "${1:-}" = "describe" && {
    describe_rule "Manage team access"
    return
  }

  local filter='
    import "githublint" as lint;

    def default_configure:
      {}
    ;

    def analyze:
      .pattern as $pattern |
      .repository |
      { location: { url } } as $issue |
      .teams | map({ slug, permission }) |
      (
        ($pattern.allowlist | map({ slug, permission })) as $allowlist |
        if contains($allowlist) then
          empty
        else
          $issue + { message: "Contains teams that should be allowed access" }
        end
      ),
      (
        ($pattern.denylist | map({ slug, permission })) as $denylist |
        if any(. as $team | $denylist | any(. == $team)) then
          $issue + { message: "Contains teams that should be denied access" }
        else
          empty
        end
      )
    ;

    lint::analyze(analyze; default_configure; $descriptor)
  '
  ! jq -ec -L"$jq_lib" \
    --argfile descriptor <(eval "$FUNCNAME" describe) \
    "$filter"
}

# Reporters

function to_tsv() {
  local org="$ORG"
  local rules_dump="$1"

  local fields=(
    kind
    id
    full_name
    default_branch
    private
    description
    fork
    language
    archived
    disabled
    created_at
    commit_activity
    teams
    exists_codeowners
    codeowners
    protected_branches
  )
  jq -r --args '$ARGS.positional + (.rules | map(.signature)) | @tsv' "${fields[*]}" < "$rules_dump"

  jq --seq -r --arg org "$org" --argfile rules "$rules_dump" '
    (
      if .resources.repositories
      then
        .resources.repositories|first|
        [
          "repository",
          .id,
          .full_name,
          .default_branch,
          .private,
          .description,
          .fork,
          .language,
          .archived,
          .disabled,
          .created_at,
          (.stats.commit_activity | length as $l | if $l == 0 then 0 else map(.total) | add / $l end),
          (.teams | map("@\($org)/\(.slug):\(.permission)")|join(";")),
          (.codeowners | length > 0),
          (.codeowners | map(.entries|map(.owners)) | flatten | unique | join(" ")),
          (.branches | map(select(.protected)) | map(.name) | join(" "))
        ]
      elif .resources.organizations
      then
        .resources.organizations|first|
        [
          "organization",
          .id,
          .login,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          .created_at,
          null,
          null,
          null,
          null,
          null
        ]
      elif .resources.users
      then
        .resources.users|first|
        [
          "user",
          .id,
          .login,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          .created_at,
          null,
          null,
          null,
          null,
          null
        ]
      else
        empty
      end
    ) + (
      .results as $results |
      $rules.rules | map(
        .signature as $signature |
        $results | map(select(.signature == $signature)) | length == 0
      )
    )
    | @tsv
  '
}

function to_json() {
  jq --seq -sc '
    def merge($rhs):
      .resources.users |= . + $rhs.resources.users |
      .resources.organizations |= . + $rhs.resources.organizations |
      .resources.repositories |= . + $rhs.resources.repositories |
      .results |= . + $rhs.results
    ;
    reduce .[] as $e ({}; merge($e))
  '
}

if [ $XTRACE -ne 0 ]
then
  declare -F
fi >&2

# main

cd "$(mktemp -d)"

rules_dump="$(mktemp)"
declare -F | grep '^declare\s\+-fx\?\s\+.\+_\(repo\|org\)_rule$' | cut -d' ' -f3 | while read -r signature
do
  eval "$signature" describe
done | jq -sc '{rules:.}' > "$rules_dump"

{
  info 'Fetching %s ...' "$SLUG"
  org_dump="$(mktemp)"
  resource_name="$(if [ -n "$ORG" ]; then echo 'organizations'; else echo 'users'; fi)"
  request "${GITHUB_API_ORIGIN}/$SLUG" | jq -c --arg resource_name "$resource_name" '{resources:{($resource_name):[.]}}' > "$org_dump"
  results_dump="$(mktemp)"
  {
    jq -r '.rules|map(.signature)|.[]|select(test("_org_rule$"))' < "$rules_dump" | while read -r func
    do
      debug 'Analysing %s about %s ...' "$ORG" "$func"
      eval "$func" analyze "$ORG" < "$org_dump" || warn '%s fail %s rule.' "$ORG" "$func"
    done | jq -sc '{results:.}' > "$results_dump"
  }
  new_json_sequence "$org_dump" "$rules_dump" "$results_dump"

  num_of_repos="$(jq -r --arg resource_name "$resource_name" '.resources[$resource_name]|first|.public_repos + .total_private_repos' "$org_dump")"
  info '%s has %d repositories.' "$SLUG" "$num_of_repos"
  info 'Fetching %s repositories ...' "$SLUG"
  list "${GITHUB_API_ORIGIN}/${SLUG}/repos" -G -d 'per_page=100' |
    jq -c "${REPO_FILTER}" |
    jq -c '.[]' | {
      count=0
      while IFS= read -r repo
      do
        full_name="$(echo "$repo" | jq -r '.full_name')"
        progress_rate=$(( ++count * 100 / num_of_repos ))

        repo_dump="$(mktemp)"
        {
          info '(%.0f%%) Fetching %s repository ...' "$progress_rate" "$full_name"
          fetch_repository "$repo" | jq -c '{resources:{repositories:[.]}}' > "$repo_dump"
        }

        results_dump="$(mktemp)"
        {
          info '(%.0f%%) Analysing %s repository ...' "$progress_rate" "$full_name"
          jq -r '.rules|map(.signature)|.[]|select(test("_repo_rule$"))' < "$rules_dump" | while read -r func
          do
            debug 'Analysing %s repository about %s ...' "$full_name" "$func"
            eval "$func" analyze "$full_name" < "$repo_dump" || warn '%s repository fail %s rule.' "$full_name" "$func"
          done | jq -sc '{results:.}' > "$results_dump"
        }

        new_json_sequence "$repo_dump" "$rules_dump" "$results_dump"
      done
      info 'Fitched %d repositories (Skipped %d repositories).' "$count" $((num_of_repos - count))
    }
} | {
  if [ "$REPORTER" = "tsv" ]
  then
    to_tsv "$rules_dump"
  elif [ "$REPORTER" = "json" ]
  then
    to_json
  else
    cat
  fi
}
