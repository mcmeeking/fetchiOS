#!/bin/bash/

DeviceDir="$HOME/Library/Application Support/FetchiOS/Devices/"
iPhoneDir="$HOME/Library/iTunes/iPhone Software Updates/"
iPadDir="$HOME/Library/iTunes/iPad Software Updates/"
iPodDir="$HOME/Library/iTunes/iPod Software Updates/"
firmwareDir="$HOME/Library/Group Containers/K36BKF7T3D.group.com.apple.configurator/Library/Caches/Firmware/"

# Logging
LOGTHIS() {
    echo "$(date "+%a %h %d %H:%M:%S") $(hostname): $1" >> "$HOME/Library/Logs/FetchiOS.log"
}

if [[ ! -d $firmwareDir ]]; then
    osascript -e "display notification \"Building firmware directory.\""
    mkdir -p "$firmwareDir"
fi

if [[ ! -d $iPhoneDir ]]; then
    mkdir -p "$iPhoneDir"
fi

if [[ ! -d $iPadDir ]]; then
    mkdir -p "$iPadDir"
fi

if [[ ! -d $iPodDir ]]; then
    mkdir -p "$iPodDir"
fi

function checkUpdate() {
    theModel="$(curl -s --retry 2 https://api.ipsw.me/v2.1/$1/latest/name)"
    LOGTHIS "Checking for new iOS version for $theModel"
    LOGTHIS "=========================================="
    IPSWURL="$(curl -s --retry 2 "https://api.ipsw.me/v2.1/$1/latest/url")"
    if [[ "$IPSWURL" == "" ]] || [[ "$theModel" == "" ]]; then
        LOGTHIS "*************** FATAL ERROR ****************"
        LOGTHIS "No URL found for $1, check network settings."
        LOGTHIS "********************************************
"
        kill -INT $$
        
    fi
    IPSWMD5="$(curl -s --retry 2 "https://api.ipsw.me/v2.1/$1/latest/md5sum")"
    IPSWname="${IPSWURL##*/}"
    IPSWversion="$(echo "$IPSWname" | awk -F '_' '{print $(NF-2)}')"
    LOGTHIS "Found iOS $IPSWversion"
    modelName="${IPSWname%%$IPSWversion*}"
    currentFilename=""
    found=0
    LOGTHIS " - Checking current files..."
    while read currentFilename; do
        currentMD5=""
        if [[ "$currentFilename" == "$IPSWname" ]]; then
            LOGTHIS "   [?] Found a matching file, analysing checksum..."
            currentMD5="$(MD5 "$currentFilename" | awk '{print $4}')"
            if [[ "$IPSWMD5" == "$currentMD5" ]]; then
                LOGTHIS "   [✓] Hashes match!"
                found=$(( found + 1 ))
            else
                LOGTHIS "   [!] Checksum mismatch!"
                LOGTHIS "       MD5 sum expected: $IPSWMD5"
                LOGTHIS "       MD5 sum received: $currentMD5"
                rm -rf "$currentFilename" && osascript -e "display notification \"Removing damaged IPSW\" with title \"Cleaning $theModel\""
                LOGTHIS "   [?] Incomplete file deleted. ($currentFilename)"
            fi
        elif [[ -n $currentFilename ]]; then
            LOGTHIS "   [!] Found an older file, deleting..."
            rm -rf "$currentFilename" && osascript -e "display notification \"Removing old iOS version\" with title \"Cleaning $theModel\""
            LOGTHIS "   [?] Old file deleted. ($currentFilename)"
        fi
    done <<< "$(ls | grep -E "${modelName}[0-9]{2}.")"
    if [[ "$found" -lt 1 ]]; then
        LOGTHIS " - No matches found locally. Downloading now..."
        osascript -e "display notification \"Downloading iOS $IPSWversion\" with title \"Updating $theModel\""
        curl -S --retry 2 --max-time 7200 -o "$IPSWname" "$IPSWURL" || LOGTHIS "[!!] Error downloading from $IPSWURL"
        LOGTHIS "   [?] Checking new file..."
        currentFilename=$(ls | grep -E "${modelName}[0-9]{2}.")
        currentMD5="$(MD5 "$currentFilename" | awk '{print $4}')"
        if [[ "$IPSWMD5" != "$currentMD5" ]]; then
            LOGTHIS "   [!] Checksum verification failed!"
            LOGTHIS "       MD5 sum expected: $IPSWMD5"
            LOGTHIS "       MD5 sum received: $currentMD5"
            if [[ -n $2 ]]; then
                LOGTHIS "   [?] Retrying..."
                checkUpdate "$1" "noretry" 
            else
                LOGTHIS "   [!] Too many retries...
"
                LOGTHIS "*************** FATAL ERROR ****************"
                LOGTHIS "Failed to update local IPSW for $modelName to iOS $IPSWversion"
                LOGTHIS "********************************************

"
                kill -INT $$
                
            fi
        else
            LOGTHIS "   [✓] Hashes match!"
            if [[ $theModel =~ "iPhone" ]]; then
                ln -s "$currentFilename" "$iPhoneDir"
            elif [[ $theModel =~ "iPad" ]]; then
                ln -s "$currentFilename" "$iPadDir"
            elif [[ $theModel =~ "iPod" ]]; then
                ln -s "$currentFilename" "$iPodDir"
            fi
        fi
        LOGTHIS "==========================================
"
    else
        LOGTHIS "==========================================
"
    fi
}

cd "$firmwareDir" || exit 1

if [[ ! -d "$DeviceDir" ]]; then
    LOGTHIS "[!] No device directory found, exiting!"
    exit 1
fi

for f in "$DeviceDir"*; do
    model="$(cat "$f")"
    if [[ "$model" != "" ]]; then
        checkUpdate "$model"
    else
        LOGTHIS "[!] No device list found! Try reinstalling."
        exit 1
    fi
done