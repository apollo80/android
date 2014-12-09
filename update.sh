#!/bin/bash

datetime=$(date +%Y.%m.%d_%H:%M)
export BUILD_HOST_32bit=1
export USE_CCACHE=1

check_packages()
{
    local packages="bison build-essential curl flex git gnupg gperf libncurses5-dev libsdl1.2-dev"

    packages+=" libwxgtk2.8-dev libxml2 libxml2-utils lzop openjdk-6-jdk openjdk-6-jre pngcrush schedtool"
    packages+=" squashfs-tools xsltproc zip zlib1g-dev"
    packages+=" g++-multilib gcc-multilib lib32ncurses5-dev lib32readline-gplv2-dev lib32z1-dev"

    for package in ${packages};
    do
        if [[ $(dpkg -l $package 2>&1 | grep "^ii .*\$" | wc -l) == "0" ]]; then
            echo "$package not exist"
        fi
    done
}

cyanogenMod_merge()
{
    local repo_path=$1
    local repo_url=$2

    echo ""
    echo "merge repo '${repo_path}' with last CyanogenMod"
    currDir=$(pwd)
    cd ${repo_path}

    if [[ $(git remote | grep -x github | wc -l) -eq 0  &&  $(git remote | grep origin | wc -l) -ne 0 ]]; then
        git remote rename origin github
    fi

    if [ $(git branch | grep default | wc -l) -ne 0 ]; then
        git branch -m default cm-11.0
    fi

    if [ $(git remote | grep github_cm | wc -l) -eq 0 ]; then
        git remote add github_cm ${repo_url}
    fi
    git fetch github cm-11.0
    git reset --hard FETCH_HEAD
    git pull --no-edit github_cm cm-11.0
    cd $currDir
}

evervolv_merge()
{
    local repo_path=$1
    local repo_url=$2

    echo ""
    echo "merge repo '${repo_path}' with last Evervolv"
    currDir=$(pwd)
    cd ${repo_path}
    if [[ $(git remote | grep -x github | wc -l) -eq 0  &&  $(git remote | grep origin | wc -l) -ne 0 ]]; then
        git remote rename origin github
    fi

    if [ $(git branch | grep default | wc -l) -ne 0 ]; then
        git branch -m default cm-11.0
    fi

    if [ $(git remote | grep github_ev | wc -l) -eq 0 ]; then
        git remote add github_ev ${repo_url}
    fi
    git fetch github cm-11.0
    git reset --hard FETCH_HEAD
    git pull --no-edit github_ev kitkat
    cd $currDir
}

undo_changes()
{
    repo_path=$1
    curr_dir=$(pwd)
    cd ${repo_path}
    git reset --hard
    cd ${curr_dir}
}

update_repo()
{
    (
    cyanogenMod_merge ".repo/manifests" "http://github.com/CyanogenMod/android"

    undo_changes external/icu4c

    echo ""
    echo "run repo sync"
    repo sync

    cyanogenMod_merge "android"                   "http://github.com/CyanogenMod/android"
    cyanogenMod_merge "build"                     "http://github.com/CyanogenMod/android_build"
    cyanogenMod_merge "frameworks/base"           "http://github.com/CyanogenMod/android_frameworks_base"
    cyanogenMod_merge "frameworks/native"         "http://github.com/CyanogenMod/android_frameworks_native"
    cyanogenMod_merge "frameworks/opt/telephony"  "http://github.com/CyanogenMod/android_frameworks_opt_telephony"
    cyanogenMod_merge "external/iproute2"         "http://github.com/CyanogenMod/android_external_iproute2"
    cyanogenMod_merge "packages/apps/Settings"    "http://github.com/CyanogenMod/android_packages_apps_Settings"

    evervolv_merge  "device/htc/bravo"        "http://github.com/Evervolv/android_device_htc_bravo"
    evervolv_merge  "device/htc/passion"      "http://github.com/Evervolv/android_device_htc_passion"
    evervolv_merge  "device/htc/qsd8k-common" "http://github.com/Evervolv/android_device_htc_qsd8k-common"
    evervolv_merge  "kernel/htc/qsd8k"        "http://github.com/Evervolv/android_kernel_htc_qsd8k"

    sed -i 's/$(TARGET_OUT)\/usr\/icu/$(TARGET_OUT_SDEXT_SYSTEM)\/usr\/icu/' external/icu4c/stubdata/Android.mk

    )  2>&1 | tee repo_sync_${datetime}.log
    gzip -9 repo_sync_${datetime}.log

    ## find conflicts in 'update'
    if [ $(gzip -dc  repo_sync_${datetime}.log | grep CONFLICT | wc -l) -ne 0 ]; then
        echo
        echo "Found CONFLICTS:"
        echo $(gzip -dc  repo_sync_${datetime}.log | grep CONFLICT)
        exit 1
    fi
}

apply_patches()
{
    if [[ -d patches ]]; then
        for patch_name in $(find patches -name *.patch -type f);
        do
            patch --verbose -p1 -i $patch_name
        done
    fi
}

build_ota_package()
{
    local product_name
    product_name=$1

    (
        echo ""
        echo "run build/envsetup.sh ..."
        source build/envsetup.sh
        echo "run breakfast ${product_name} ..."
        breakfast ${product_name}

        echo "run croot ..."
        croot

        echo "run brunch ${product_name} ..."
        brunch ${product_name}

    ) 2>&1 | tee build_${product_name}_${datetime}.log

    sed 's/\o33\[3[1-6]m//g' build_${product_name}_${datetime}.log  | sed 's/\o33\[4[1-6]m//g' | sed 's/\o33\[[01]m//g'| sed 's/\o33\[m//g' > build_${product_name}_${datetime}_nc.log
    gzip -9 build_${product_name}_${datetime}.log
    gzip -9 build_${product_name}_${datetime}_nc.log
}


usage()
{
    echo -e "USAGE:   $1 [-h|--help] [-c|--clear] [--no-update] [-b|--build <devices list>]"
    echo -e "\t-h|--help   - this help"
    echo -e "\t-c|--clear  - clear \"out\" directory"
    echo -e "\t--no-update - don't update source code"
    echo -e "\t-b|--build <device1 device2 ...>"
    echo -e "\t            - space separated list of device"
    exit 0
}


################################################################################################
CLEAR_BEFORE_BUILD="NO"
NEED_SOURCE_UPDATE="YES"
BUILD_LIST="passion bravo"

SCRIPT_NAME=$0

while [[ $# > 0 ]]
do
    key=$1
    shift

    case $key in
        -c|--clear)
            CLEAR_BEFORE_BUILD="YES"
            ;;

        --no-update)
            NEED_SOURCE_UPDATE="NO"
            ;;

        -h|--help)
            usage $SCRIPT_NAME
            break
            ;;

        -b|--build)
            BUILD_LIST="$@"
            break
            ;;
    esac
done

#echo "CLEAR_BEFORE_BUILD = $CLEAR_BEFORE_BUILD"
#echo "NEED_SOURCE_UPDATE = $NEED_SOURCE_UPDATE"
#echo "BUILD_LIST         = $BUILD_LIST"

#----------
# checking the existence of the necessary packages
check_packages
#----------


#----------
# update source
if [[ "$NEED_SOURCE_UPDATE" == "YES" ]]; then
    update_repo
    apply_patches
fi
#----------

#----------
# Clean out directory
if [[ "$CLEAR_BEFORE_BUILD" == "YES" && -d out ]]; then
    rm -rf out/*
fi
#----------


#----------
# build products
for productName in $BUILD_LIST;
do
    export RELEASE_TYPE=CM_NIGHTLY
    prebuilts/misc/linux-x86/ccache/ccache -M 50G
    build_ota_package $productName
done
#----------
