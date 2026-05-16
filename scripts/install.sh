#!/usr/bin/env bash
set -euo pipefail

readonly REPO="kamilpopowicz/PasswordMonitor"
readonly ASSET_NAME="PasswordMonitor.app.zip"
readonly APP_NAME="PasswordMonitor.app"
readonly INSTALL_DIR="/Applications"
readonly DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/${ASSET_NAME}"

tmp_dir="$(/usr/bin/mktemp -d)"
cleanup() {
  /bin/rm -rf "${tmp_dir}"
}
trap cleanup EXIT

zip_path="${tmp_dir}/${ASSET_NAME}"
extract_dir="${tmp_dir}/extract"
app_path="${extract_dir}/${APP_NAME}"
target_path="${INSTALL_DIR}/${APP_NAME}"

/bin/mkdir -p "${extract_dir}"

echo "Downloading ${ASSET_NAME}..."
/usr/bin/curl -fL --retry 3 --connect-timeout 15 -o "${zip_path}" "${DOWNLOAD_URL}"

echo "Extracting ${APP_NAME}..."
/usr/bin/ditto -x -k "${zip_path}" "${extract_dir}"

if [[ ! -d "${app_path}" ]]; then
  echo "Error: ${APP_NAME} was not found in the release archive." >&2
  exit 1
fi

echo "Installing ${APP_NAME} to ${INSTALL_DIR}..."
if [[ -w "${INSTALL_DIR}" ]]; then
  /usr/bin/ditto "${app_path}" "${target_path}"
else
  /usr/bin/sudo /usr/bin/ditto "${app_path}" "${target_path}"
fi

echo "Installed ${target_path}"
