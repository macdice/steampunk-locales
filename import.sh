#!/usr/bin/sh
#
# Import glibc locale definitions from various GNU/Linux distributions and
# compile them on the present system, which should be a later glibc system.
#
# XXX Could potentially import to non-glibc systems too?

set -e

work="work"
output="imported-locales"

fetch_locales_deb()
{
    distribution="$1"
    url="$2"
    package="$(basename $url)"

    mkdir -p "$work/$distribution/charmaps"

    # pull down the package if we haven't already
    package_path="$work/$distribution/$package"
    if [ ! -f "$package_path" ] ; then
        echo "Fetching $distribution package $package from $url"
        curl -f -s -S "$url" > "$package_path.tmp"
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
            ar x "../../../$package_path"
            tar xf data.tar.*
            rm -f data.tar.* debian-binary control.tar.*
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
}

compile_locales()
{
    distribution="$1"

    fakeroot_path="$work/$distribution/fakeroot"
    supported_path="$work/$distribution/SUPPORTED"

    # debian invented its own definition of C.UTF-8 before glibc 2.35 invented
    # codepoint_collation, but it wasn't listed in SUPPORTED, so add it.
    # newer debian has it in there already, but duplicates do nothing below
    cp "$fakeroot_path/usr/share/i18n/SUPPORTED" "$supported_path"
    echo "C.UTF-8 UTF-8" >> "$supported_path"

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
    done < "$supported_path"
}

import_locales_deb()
{
    distribution="$1"
    url="$2"

    echo "Importing locales from $distribution..."

    fetch_locales_deb "$distribution" "$url"
    compile_locales "$distribution"
}

import_locales_deb_latest()
{
	# pull down the current list of packages for this distribution
	distribution="$1"
	deb_distname="$2"
	package_list="$work/$distribution/packagelist.txt"
	mkdir -p "$(dirname $package_list)"
	if [ ! -e "$package_list" ] ; then
		url="https://packages.debian.org/$deb_distname/allpackages?format=txt.gz"
		echo "Fetching $url"
		curl -f -s -S "$url" | gzip -d > "$package_list.tmp"
		mv "$package_list.tmp" "$package_list"
	fi

	# is it marked [security]?  that affects the URL
	# TODO: this is using http, but not yet verifying the signature
	package_dirs="main/g/glibc"
	package_name="locales"
	package_arch="all"

	# extract the current version of the locales package
	package_version="$(grep -E "^$package_name " "$package_list" | sed "s/$package_name (//;s/).*//")"

	if grep "^$package_name .*\[security\]" $package_list > /dev/null ; then
		package_url="http://security.debian.org/debian-security/pool/updates/${package_dirs}/${package_name}_${package_version}_${package_arch}.deb"
	else
		package_url="http://ftp.debian.org/debian/pool/${package_dirs}/${package_name}_${package_version}_${package_arch}.deb"
	fi

	import_locales_deb "$distribution" "$package_url"
}

set -e

import_locales_deb_latest "debian11" "bullseye"
import_locales_deb_latest "debian12" "bookworm"
import_locales_deb_latest "debian13" "trixie"
import_locales_deb_latest "debian14" "forky"

# TODO: find latest from ubuntu
import_locales_deb "ubuntu18" \
    "http://launchpadlibrarian.net/582642195/locales_2.27-3ubuntu1.5_all.deb"
import_locales_deb "ubuntu20" \
    "http://launchpadlibrarian.net/795475508/locales_2.31-0ubuntu9.18_all.deb"
import_locales_deb "ubuntu22" \
    "http://launchpadlibrarian.net/773665459/locales_2.39-0ubuntu8.4_all.deb"
