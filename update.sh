#!/bin/bash

datetime=$(date +%Y.%m.%d_%H:%M)

cyanogenMod_merge()
{
    local repo_path=$1
    local repo_url=$2

    echo ""
    echo "merge repo '${repo_path}' with last CyanogenMod"
    currDir=$(pwd)
    cd ${repo_path}
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
    if [ $(git remote | grep github_ev | wc -l) -eq 0 ]; then
        git remote add github_ev ${repo_url}
    fi
    git fetch github cm-11.0
    git reset --hard FETCH_HEAD
    git pull --no-edit github_ev kitkat
    cd $currDir
}

build_ota_package()
{
    local product_name
    product_name=$1

    (
        echo ""
        echo "run build/envsetup.sh ..."
        . build/envsetup.sh
        echo "run lunch cm_${product_name}-userdebug ..."
        lunch cm_${product_name}-userdebug

        echo "run make -j8 otapackage ..."
        make -j8 otapackage

    ) 2>&1 | tee build_${product_name}_${datetime}.log

    sed 's/\o33\[3[1-6]m//g' build_${product_name}_${datetime}.log  | sed 's/\o33\[4[1-6]m//g' | sed 's/\o33\[[01]m//g'| sed 's/\o33\[m//g' > build_${product_name}_${datetime}_nc.log
    gzip -9 build_${product_name}_${datetime}.log
    gzip -9 build_${product_name}_${datetime}_nc.log
}


(
    cyanogenMod_merge ".repo/manifests" "http://github.com/CyanogenMod/android"

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

    #evervolv_merge  "device/htc/bravo"        "http://github.com/Evervolv/android_device_htc_bravo"
    #evervolv_merge  "device/htc/passion"      "http://github.com/Evervolv/android_device_htc_passion"
    #evervolv_merge  "device/htc/qsd8k-common" "http://github.com/Evervolv/android_device_htc_qsd8k-common"
    #evervolv_merge  "kernel/htc/qsd8k"        "http://github.com/Evervolv/android_kernel_htc_qsd8k"

    sed -i 's/$(TARGET_OUT)\/usr\/icu/$(TARGET_OUT_SDEXT_SYSTEM)\/usr\/icu/' external/icu4c/stubdata/Android.mk

)  2>&1 | tee repo_sync_${datetime}.log
gzip -9 repo_sync_${datetime}.log

if [ $(gzip -dc  repo_sync_${datetime}.log | grep CONFLICT | wc -l) -ne 0 ]; then
    echo
    echo "Found CONFLICTS:"
    echo $(gzip -dc  repo_sync_${datetime}.log | grep CONFLICT)
fi


################################################################################################


if [ "$1" = "--build" ]; then

    if [ -n "$2" ]; then
        productList=$2
    else
        productList="passion bravo"
    fi

    for productName in $productList;
    do
        if [ -d out/target/product/$productName ]; then
            echo "rm -rf out/target/product/$productName "
            rm -rf out/target/product/$productName/*
        fi

        build_ota_package $productName
    done
fi
