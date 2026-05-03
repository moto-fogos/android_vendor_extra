release() {
    local device="$1"

    if [ -z "${device}" ]; then
        echo "[ERROR] Usage: release <device>"
        return 1
    fi

    echo "[INFO] Generating PixelOS OTA JSON for device: ${device}"

    local top="${ANDROID_BUILD_TOP}"
    local out_dir="${top}/out/target/product/${device}"
    local ota_dir="${top}/vendor/extra/ota"
    local ota_device_dir="${ota_dir}/${device}"
    local json_path="${ota_device_dir}/${device}.json"

    if [ ! -d "${out_dir}" ]; then
        echo "[ERROR] Output dir not found: ${out_dir}"
        return 1
    fi

    rm -rf "${ota_dir}"
    git clone https://github.com/pixelos-fogos/ota-update.git "${ota_dir}" || return 1
    cd "${ota_dir}" || return 1
    git checkout main 2>/dev/null || git checkout master

    local ota
    ota="$(printf "%s\n" "${out_dir}/PixelOS_${device}-"*.zip | sort | tail -n1)"

    if [ ! -f "${ota}" ]; then
        echo "[ERROR] PixelOS zip not found for ${device}"
        return 1
    fi

    local filename
    filename="$(basename "${ota}")"

    echo "[INFO] Using ZIP: ${filename}"

    local build_props="${out_dir}/system/build.prop"

    if [ ! -f "${build_props}" ]; then
        echo "[ERROR] build.prop not found"
        return 1
    fi

    local datetime
    datetime="$(grep -oP '(?<=^ro.build.date.utc=).*' "${build_props}")"

    if [ -z "${datetime}" ]; then
        echo "[ERROR] ro.build.date.utc not found"
        return 1
    fi

    local id
    if [ -f "${ota}.sha256sum" ]; then
        id="$(awk '{print $1}' "${ota}.sha256sum")"
    else
        id="$(sha256sum "${ota}" | awk '{print $1}')"
    fi

    local size
    size="$(stat -c%s "${ota}")"

    local romtype="Monthly"

    local version
    version="$(echo "${filename}" | grep -oP '(?<=PixelOS_'"${device}"'-)\d+')"

    local url="https://sourceforge.net/projects/rmdn-stuff/files/${device}/pixelos/${filename}/download"

    mkdir -p "${ota_device_dir}"

    jq -n \
        --argjson datetime "${datetime}" \
        --arg filename "${filename}" \
        --arg id "${id}" \
        --arg romtype "${romtype}" \
        --argjson size "${size}" \
        --arg url "${url}" \
        --arg version "${version}" \
        '{
            response: [
                {
                    datetime: $datetime,
                    filename: $filename,
                    id: $id,
                    romtype: $romtype,
                    size: $size,
                    url: $url,
                    version: $version
                }
            ]
        }' > "${json_path}"

    echo
    echo "[DONE] OTA JSON generated successfully"
    echo " Path : ${json_path}"
    echo

    git status --short
}

sign() {
    local top="${ANDROID_BUILD_TOP}"
    local keys_dir="${top}/vendor/lineage-priv/keys"
    local keys_repo="https://github.com/heybyben/android_vendor_lineage-priv_keys"

    if [ ! -d "${keys_dir}/.git" ]; then
        echo "[INFO] Cloning signing keys..."
        mkdir -p "${top}/vendor/lineage-priv"
        git clone "${keys_repo}" "${keys_dir}" || return 1
    else
        echo "[INFO] Keys already present, skipping clone"
    fi
}

enable_patch() {
    cd "${ANDROID_BUILD_TOP}" || exit 1
    PATCHES_PATH="${ANDROID_BUILD_TOP}/vendor/extra/patches"
    TARGET_REPO="${ANDROID_BUILD_TOP}/vendor/custom"
    [ ! -d "$PATCHES_PATH" ] && return 0
    [ ! -d "$TARGET_REPO/.git" ] && {
        echo "vendor/custom is not a git repo"
        exit 1
    }
    cd "$TARGET_REPO" || exit 1
    echo "Applying patches to vendor/custom..."
    if ! git am "$PATCHES_PATH"/000{1,2}-*.patch --no-gpg-sign; then
        echo "Failed to apply patches to vendor/custom"
        git am --abort
        exit 1
    fi
    echo "All vendor/custom patches applied successfully"
    cd "${ANDROID_BUILD_TOP}" || exit 1
}
