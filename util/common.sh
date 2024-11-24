source ./versions.sh

if [[ "$(uname)" == "Darwin" ]]; then
    NPROC=$(sysctl -n hw.logicalcpu)
else
    NPROC=$(nproc)
fi

# Print the GCC and G++ used in this build
clone_if_not_exists() {
  local BRANCH_OR_TAG=$1
  local REPO_URL=$2
  local TARGET_DIR=${3:-$(basename "$REPO_URL" .git)}

  # Check if the target directory exists
  if [ -d "$TARGET_DIR" ]; then
    echo "[+] Directory $TARGET_DIR already exists locally, skipping fetch..."
  else
    echo "[+] Fetching $TARGET_DIR from $REPO_URL..."
    git clone --depth 1 --single-branch --branch "$BRANCH_OR_TAG" "$REPO_URL" "$TARGET_DIR"
    rm -rf "$TARGET_DIR/.git"
  fi
}

# Download and extract a library using either wget or curl.
download_and_extract() {
  local lib_name=$1
  local lib_version=$2
  local url=$3

  if which wget >/dev/null; then
    dl='wget'
  else
    dl='curl -LO'
  fi

  if [ ! -e "${lib_name}" ]; then
    ${dl} "${url}-${lib_version}.tar.bz2"
    tar -xjf "${lib_name}-${lib_version}.tar.bz2"
    mv "${lib_name}-${lib_version}" "${lib_name}"
  fi
}

download_prerequisites_binutils() {
  # Download libgmp and libmpfr
  download_and_extract "gmp" "${LIBGMP_VERS}" "https://ftp.gnu.org/gnu/gmp/gmp"
  download_and_extract "mpfr" "${LIBMPFR_VERS}" "https://ftp.gnu.org/gnu/mpfr/mpfr"
}
