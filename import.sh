#!/usr/bin/sh

work="work"
output="imported-locales"

import_locales_deb()
{
    distribution="$1"
    url="$2"
    package="$(basename $url)"

    echo "Importing locales from $distribution..."

    mkdir -p "$work/$distribution/charmaps"

    # pull down the package if we haven't already
    package_path="$work/$distribution/$package"
    if [ ! -f "$package_path" ] ; then
        echo "Fetching $distribution package $package..."
        curl -s "$url" > "$package_path.tmp"
        mv "$package_path.tmp" "$package_path"
    fi

    # unpack the interesting contents into fakeroot if we haven't already
    fakeroot_path="$work/$distribution/fakeroot"
    if [ ! -e "$fakeroot_path" ] ; then
        rm -fr "$fakeroot_path.tmp"
        mkdir -p "$fakeroot_path.tmp"
        echo "Extracting $distribution package $package..."
        (
            cd "$fakeroot_path.tmp"
            ar -x "../../../$package_path" data.tar.xz
            tar xf data.tar.xz
            rm data.tar.xz
        )
        mv "$fakeroot_path.tmp" "$fakeroot_path"
    fi

    # unpack the charsets if we haven't already
    charmaps_path="$work/$distribution/charmaps"
    for charmap_gz in $(ls "$fakeroot_path/usr/share/i18n/charmaps") ; do
        charmaps_gz_path="$fakeroot_path/usr/share/i18n/charmaps"
        charmap="$(basename "$charmap_gz" .gz)"
        charmap_path="$charmaps_path/$charmap"
        if [ ! -e "$charmap_path" ] ; then
            echo "Extracting $distribution charmap $charmap..."
            gzip -d < "$charmaps_gz_path/$charmap_gz" > "$charmap_path.tmp"
            mv "$charmap_path.tmp" "$charmap_path"
        fi
    done

    # compile all locales if we haven't already
    while read -r name charmap ; do
      name_base="$(echo "$name" | sed 's/\..*//')"
      name_charmap="$(echo "$name" | sed 's/^[^.]*//')"
      name_charmap_munged="$(echo "$name_charmap" | sed 's/[^.a-zA-Z0-9]//g' | tr '[:upper:]' '[:lower:]')"
      locale_path="$output/$distribution/$(echo "$name_base$name_charmap_munged")"
      if [ ! -e "$locale_path" ] ; then
         echo "Compiling $locale_path..."
         mkdir -p "$output/$distribution"
         rm -fr "$locale_path.tmp"
         I18NPATH="$work/$distribution/fakeroot/usr/share/i18n" localedef -f "$work/$distribution/charmaps/$charmap" -i "$work/$distribution/fakeroot/usr/share/i18n/locales/$name_base" "$locale_path.tmp"
         mv "$locale_path.tmp" "$locale_path"
      fi
    done < "$fakeroot_path/usr/share/i18n/SUPPORTED"
}

set -e

# TODO It would be better to discover the latest released package than have
# these hard-coded versions!

import_locales_deb "debian11" \
    "http://security.debian.org/debian-security/pool/updates/main/g/glibc/locales_2.28-10+deb10u4_all.deb"
import_locales_deb "debian12" \
    "http://http.us.debian.org/debian/pool/main/g/glibc/locales_2.36-9+deb12u10_all.deb"

import_locales_deb "ubuntu18" \
    "http://launchpadlibrarian.net/582642195/locales_2.27-3ubuntu1.5_all.deb"
import locales_deb "ubuntu20" \
    "http://launchpadlibrarian.net/795475508/locales_2.31-0ubuntu9.18_all.deb"
import locales_deb "ubuntu22" \
    "http://launchpadlibrarian.net/773665459/locales_2.39-0ubuntu8.4_all.deb"
