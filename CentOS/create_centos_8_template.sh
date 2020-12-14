#!/bin/bash

#creates a Centos8 kickstart based template
#This script requires a working metalcloud-cli and jq tools.

#Note this will delete the existing template instead of updating it.

if [ "$#" -ne 2 ]; then
    echo "syntax: $0 <template-id> <os-version (eg: 8.)>"
    exit
fi

TEMPLATE_VERSION="$2" 
TEMPLATE_DISPLAY_NAME="CentOS $TEMPLATE_VERSION"
TEMPLATE_DESCRIPTION="$TEMPLATE_DISPLAY_NAME"
TEMPLATE_LABEL=$1
TEMPLATE_ROOT="centos/$TEMPLATE_VERSION"


SOURCES="./$TEMPLATE_VERSION"

MC="metalcloud-cli"

DATACENTER_NAME="$METALCLOUD_DATACENTER"
REPO_URL=`metalcloud-cli datacenter get --id $DATACENTER_NAME --show-config --format json | jq ".[0].CONFIG | fromjson |.repoURLRoot" -r`
TEMPLATE_BASE=$REPO_URL/$TEMPLATE_ROOT

if $MC os-template get --id "$TEMPLATE_LABEL" 2>&1 >/dev/null; then
    if $MC os-template delete --id "$TEMPLATE_LABEL" --autoconfirm 2>&1 >/dev/null; then
        OS_TEMPLATE_COMMAND=create
        OS_TEMPLATE_FLAG=label
    else
        OS_TEMPLATE_COMMAND=update
        OS_TEMPLATE_FLAG=id
    fi
else
    OS_TEMPLATE_COMMAND=create
    OS_TEMPLATE_FLAG=label
fi

#create the template
$MC os-template $OS_TEMPLATE_COMMAND \
--$OS_TEMPLATE_FLAG "$TEMPLATE_LABEL" \
--display-name "$TEMPLATE_DISPLAY_NAME" \
--description "$TEMPLATE_DESCRIPTION" \
--boot-type uefi_only \
--os-architecture "x86_64" \
--os-type "CentOS" \
--os-version "$TEMPLATE_VERSION" \
--use-autogenerated-initial-password \
--initial-user "root" \
--initial-ssh-port 22 \
--boot-methods-supported "local_drives"

#first param is asset name, 
#second param is asset url relative to $TEMPLATE_BASE 
#third param is usage
function addBinaryURLAsset {
        
    $MC asset list --format json  | jq ".[] | select(.FILENAME==\"${1}-${TEMPLATE_LABEL}\")|.ID" -r | xargs -l metalcloud-cli asset delete --autoconfirm --id
    $MC asset create --url "$TEMPLATE_BASE/$2" --filename "$1-$TEMPLATE_LABEL" --mime "application/octet-stream" --usage "$3" --return-id
    $MC asset associate --id "$1-$TEMPLATE_LABEL" --template-id $TEMPLATE_LABEL -path "/$1"
}

#firt param is file name on disk
#second param is path in tftp/http
#third param is params accepted
function addFileAsset {
    $MC asset list --format json  |jq ".[] | select(.FILENAME==\"${1}-$TEMPLATE_LABEL\")|.ID" -r | xargs -l metalcloud-cli asset delete --autoconfirm --id
    cat $SOURCES/$1 | $MC asset create --filename "$1-$TEMPLATE_LABEL" --mime "text/plain" --pipe
    $MC asset associate --id "$1-$TEMPLATE_LABEL" --template-id $TEMPLATE_LABEL --path "$2"
}

#add bootx64 (pre-bootloader uefi for secure boot)
TEMPLATE_INSTALL_BOOTLOADER_ASSET=`addBinaryURLAsset "bootx64.efi" "BaseOS/x86_64/kickstart/EFI/BOOT/BOOTX64.EFI" "bootloader"`

#set the bootx64 bootloader as the template's default bootloader
metalcloud-cli os-template update --id "$TEMPLATE_LABEL" --install-bootloader-asset "$TEMPLATE_INSTALL_BOOTLOADER_ASSET"

#add grub bootloader
addBinaryURLAsset "grubx64.efi" "BaseOS/x86_64/kickstart/EFI/BOOT/grubx64.efi"

#add grub config file
addFileAsset 'grubx64.cfg' '/grub.cfg'

#add vmlinuz
addBinaryURLAsset 'vmlinuz' 'BaseOS/x86_64/kickstart/images/pxeboot/vmlinuz'

#add initrd.img
addBinaryURLAsset 'initrd.img' 'BaseOS/x86_64/kickstart/images/pxeboot/initrd.img'

#add kickstart file ks.cfg
addFileAsset 'ks.cfg' '/ks.cfg'

#add snmpd.conf
addFileAsset 'snmpd.conf' '/snmpd.conf'

