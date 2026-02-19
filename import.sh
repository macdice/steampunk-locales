#!/usr/bin/sh
#
# Import glibc locale definitions from various GNU/Linux distributions and
# compile them on the present system, which should be a later glibc system.
#
# XXX Could potentially import to non-glibc systems too?

set -e

work="work"
output="imported-locales"
localedef_version="$(localedef --version | head -1)"

fetch_locales_deb()
{
    distribution="$1"
    url="$2"
    package="$(basename $url)"

    mkdir -p "$work/$distribution/charmaps"

	echo <<EOF > "$work/$distribution/PROVENANCE"
Locales cross-compiled using:

$localdef_version

Definitions obtained from:

$url
EOF

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
    #compile_locales "$distribution"
}

# Handles Debian and Ubuntu
import_locales_debianlike_latest()
{
	distribution="$1"
	codename="$2"
	repo_base_url="$3"

	package_list="$work/$distribution/Packages"

	# In older Debian and all Ubuntu there is no "binary-all" so we have to
	# look in "binary-amd64"
	if curl -f -s -S "$repo_base_url/dists/$codename/main" | grep "binary-all" > /dev/null ; then
		arch="all"
	else
		arch="amd64"
	fi

	mkdir -p "$(dirname $package_list)"
	if [ ! -e "$package_list" ] ; then
		url="$repo_base_url/dists/$codename/main/binary-$arch/Packages.gz"
		echo "Fetching $url"
		curl -f -s -S "$url" | gzip -d > "$package_list.tmp"
		mv "$package_list.tmp" "$package_list"
	fi

	package_info="$work/$distribution/locales.package"
	if [ ! -e "$package_info" ] ; then
		awk 'BEGIN { in_zone = 0; } /^Package: locales$/ { in_zone = 1; print; } /^ *$/ { in_zone = 0; } in_zone { print; }' "$package_list" > "$package_info.tmp"
		mv "$package_info.tmp" "$package_info"
	fi

	package_version="$( grep "Version: " "$package_info" | sed 's/^[^:]*: //')"
	package_filename="$( grep "Filename: " "$package_info" | sed 's/^[^:]*: //')"
	package_url="$repo_base_url/$package_filename"

	import_locales_deb "$distribution" "$package_url"
}

import_locales_debian_latest()
{
	distribution="$1"
	codename="$2"

	# figure out if it's in current or archive repos
	if curl -f -s -S "https://archive.debian.org/debian/dists/" | grep ">$codename/" > /dev/null ; then
		repo_base_url="https://archive.debian.org/debian"
	else
		repo_base_url="http://ftp.debian.org/debian"
	fi

	import_locales_debianlike_latest "$distribution" "$codename" "$repo_base_url"
}

import_locales_ubuntu_latest()
{
	distribution="$1"
	codename="$2"

	repo_base_url="https://archive.ubuntu.com/ubuntu"

	import_locales_debianlike_latest "$distribution" "$codename" "$repo_base_url"
}



#import_locales_debian_latest "debian14" "forky"
#import_locales_debian_latest "debian13" "trixie"
import_locales_debian_latest "debian12" "bookworm"
import_locales_debian_latest "debian11" "bullseye"
import_locales_debian_latest "debian10" "buster"
import_locales_debian_latest "debian9" "stretch"
import_locales_debian_latest "debian8" "jessie"
import_locales_debian_latest "debian7" "wheezy"
import_locales_debian_latest "debian6" "squeeze"

import_locales_ubuntu_latest "ubuntu26.04" "resolute"
import_locales_ubuntu_latest "ubuntu24.04" "noble"
import_locales_ubuntu_latest "ubuntu22.04" "jammy"
import_locales_ubuntu_latest "ubuntu20.04" "focal"
import_locales_ubuntu_latest "ubuntu18.04" "bionic"
import_locales_ubuntu_latest "ubuntu16.04" "xenial"
import_locales_ubuntu_latest "ubuntu14.04" "trusty"
