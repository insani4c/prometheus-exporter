#!/bin/bash

TAG_VERSION=$(git describe --tags --abbrev=0)
VERSION=$(echo $TAG_VERSION|sed -e 's/^v//')
BUILD_DATE=$(date -R)

sed -i -e "s/%TAG_VERSION%/${VERSION}-${BUILD_NUMBER}/" -e "s/%BUILD_DATE%/$BUILD_DATE/" debian/changelog

mkdir -p build
cp -r debian usr etc lib build/

cd build

DEB_BUILD_OPTIONS=nostrip dpkg-buildpackage -b --no-sign
