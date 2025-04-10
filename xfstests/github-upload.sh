#/usr/bin/env bash
#
# Script to upload xfstests results from a deployed node to Github repository
#

set -x

# Function to extract owner and repo from GitHub URL
parse_github_url() {
    local github_url="$1"
    local path="${github_url#https://github.com/}"
    local owner="${path%%/*}"
    local remaining="${path#*/}"
    local repo="${remaining%%/*}"
    echo "$owner" "$repo"
}

upload() {
    local directory=$1
    local file=$2
    local reldir=$3
    local path=$(realpath --relative-to="$reldir" $file)

    # Encode file in base64
    encoded_content=$(base64 --wrap 0 --ignore-garbage "$file")
    if [ $? -ne 0 ]; then
        echo "Error: Failed to encode file in base64"
        exit 1
    fi

    # To replace a file we need its SHA
    filesha=$(curl -L \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/repos/$owner/$repo/contents/$path" | jq ".sha")

    curl -L \
      -X PUT \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/repos/$owner/$repo/contents/$directory/$path" \
      -d "{\"message\":\"Upload file $path\",\"committer\":{\"name\":\"$(hostname)\",\"email\":\"$(hostname)@example.com\"},\"content\":\"$encoded_content\",\"sha\":$filesha}"
}

if [ "$#" -ne 3 ]; then
    echo "Error: Script requires exactly 3 arguments"
    echo "Usage: $0 <url> <directory> <file/directory>"
    exit 1
fi

url="$1"
directory="$2"
target="$(readlink -f $3)"

if [ -z "${GITHUB_TOKEN}" ]; then
    echo "Error: GITHUB_TOKEN environment variable is not set"
    exit 1
fi

read owner repo <<< $(parse_github_url "$url")
if [ -f "$target" ]; then
   echo "$target is a file"
   upload $directory $target $(dirname $target)
elif [ -d "$target" ]; then
   echo "$target is a directory"
   find $target -mindepth 1 -type f -print0 |
    while IFS= read -r -d '' line; do
        upload $directory $line $(realpath $target)
    done
else
   echo "$target: don't know how to upload"
   exit 1
fi
