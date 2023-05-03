#!/bin/bash
#================================================================
# HEADER
#================================================================
#% SYNOPSIS
#+    ${SCRIPT_NAME} [OPTIONS] <provider> [additional arguments]
#%
#% DESCRIPTION
#%    Handle all the steps to setup the infrastructure and initialize wireguard.
#%
#% ARGUMENTS
#%    <provider>                    The provider to use. Valid options are: [openstack, oracle, gcp, wireguard].
#%                                  The last one will use Ansible to install and configure wireguard.
#%                                  Must be called after one of the other options.
#%    [additional arguments]        Additional arguments to pass to the provider
#%
#% OPTIONS
#%    -h, --help                    Help section
#%    -d, --destroy                 When using a terraform provider, destroy the infrastructure
#%    -k, --key                     Name oo the private key to create or use (key.pem)
#%    -a, --ask-vault-pass          Ansible will ask for a password to decrypt the vault with
#%    -y, --yes                     Answer yes to all questions
#%    -n, --no-color                Disble color output
#%    -v, --version                 Script information
#%
#% EXAMPLES
#%    ${SCRIPT_NAME} openstack
#%    ${SCRIPT_NAME} oracle -y
#%
#================================================================
#- IMPLEMENTATION
#-    version         ${SCRIPT_NAME} 0.0.1
#-    author          TendTo
#-    copyright       Copyright (c) https://github.com/TendTo
#-    license         GNU General Public License
#-
#================================================================
# END_OF_HEADER
#================================================================


# DESC: Usage help and version info
# ARGS: None
# OUTS: None
# NOTE: Used to document the usage of the script
#       and to display its version when requested or
#       if some arguments are not valid
usage() { printf "Usage: "; head -${script_headsize:-99} ${0} | grep -e "^#+" | sed -e "s/^#+[ ]*//g" -e "s/\${SCRIPT_NAME}/${script_name}/g" ; }
usagefull() { head -${script_headsize:-99} ${0} | grep -e "^#[%+-]" | sed -e "s/^#[%+-]//g" -e "s/\${SCRIPT_NAME}/${script_name}/g" ; }
scriptinfo() { head -${script_headsize:-99} ${0} | grep -e "^#-" | sed -e "s/^#-//g" -e "s/\${SCRIPT_NAME}/${script_name}/g"; }

# DESC: Generic script initialisation
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: $orig_cwd: The current working directory when the script was run
#       $script_path: The full path to the script
#       $script_dir: The directory path of the script
#       $script_name: The file name of the script
#       $script_params: The original parameters provided to the script
#       $ta_none: The ANSI control code to reset all text attributes
# NOTE: $script_path only contains the path that was used to call the script
#       and will not resolve any symlinks which may be present in the path.
#       You can use a tool like realpath to obtain the "true" path. The same
#       caveat applies to both the $script_dir and $script_name variables.
function script_init() {
    # Useful variables
    readonly orig_cwd="$PWD"
    readonly script_params="$*"
    readonly script_path="${BASH_SOURCE[0]}"
    script_dir="$(dirname "$script_path")"
    script_name="$(basename "$script_path")"
    readonly script_dir script_name
    readonly ta_none="$(tput sgr0 2> /dev/null || true)"
    readonly script_headsize=$(head -200 ${0} |grep -n "^# END_OF_HEADER" | cut -f1 -d:)
}

# DESC: Initialise colour variables
# ARGS: None
# OUTS: Read-only variables with ANSI control codes
# NOTE: If --no-color was set the variables will be empty. The output of the
#       $ta_none variable after each tput is redundant during normal execution,
#       but ensures the terminal output isn't mangled when running with xtrace.
function color_init() {
    # Text attributes
    readonly ta_bold="$(tput bold 2> /dev/null || true)"
    printf '%b' "$ta_none"
    readonly ta_uscore="$(tput smul 2> /dev/null || true)"
    printf '%b' "$ta_none"
    readonly ta_blink="$(tput blink 2> /dev/null || true)"
    printf '%b' "$ta_none"
    readonly ta_reverse="$(tput rev 2> /dev/null || true)"
    printf '%b' "$ta_none"
    readonly ta_conceal="$(tput invis 2> /dev/null || true)"
    printf '%b' "$ta_none"

    # Foreground codes
    readonly fg_black="$(tput setaf 0 2> /dev/null || true)"
    printf '%b' "$ta_none"
    readonly fg_blue="$(tput setaf 4 2> /dev/null || true)"
    printf '%b' "$ta_none"
    readonly fg_cyan="$(tput setaf 6 2> /dev/null || true)"
    printf '%b' "$ta_none"
    readonly fg_green="$(tput setaf 2 2> /dev/null || true)"
    printf '%b' "$ta_none"
    readonly fg_magenta="$(tput setaf 5 2> /dev/null || true)"
    printf '%b' "$ta_none"
    readonly fg_red="$(tput setaf 1 2> /dev/null || true)"
    printf '%b' "$ta_none"
    readonly fg_white="$(tput setaf 7 2> /dev/null || true)"
    printf '%b' "$ta_none"
    readonly fg_yellow="$(tput setaf 3 2> /dev/null || true)"
    printf '%b' "$ta_none"

    # Background codes
    readonly bg_black="$(tput setab 0 2> /dev/null || true)"
    printf '%b' "$ta_none"
    readonly bg_blue="$(tput setab 4 2> /dev/null || true)"
    printf '%b' "$ta_none"
    readonly bg_cyan="$(tput setab 6 2> /dev/null || true)"
    printf '%b' "$ta_none"
    readonly bg_green="$(tput setab 2 2> /dev/null || true)"
    printf '%b' "$ta_none"
    readonly bg_magenta="$(tput setab 5 2> /dev/null || true)"
    printf '%b' "$ta_none"
    readonly bg_red="$(tput setab 1 2> /dev/null || true)"
    printf '%b' "$ta_none"
    readonly bg_white="$(tput setab 7 2> /dev/null || true)"
    printf '%b' "$ta_none"
    readonly bg_yellow="$(tput setab 3 2> /dev/null || true)"
    printf '%b' "$ta_none"
}

# DESC: Parameter parser
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: Variables indicating command-line parameters and options
function parse_args
{
    # Local variable
    local param
    # Positional args
    local args=()

    # Named args
    key_name="key.pem"
    ask_vault_pass=""

    # nNmed args
    while [ $# -gt 0 ]; do
        param="$1"
        shift
        case "$param" in
            -h )
                usage
                exit 0
            ;;
            --help )
                usagefull
                exit 0
            ;;
            -v | --version )
                scriptinfo
                exit 0
            ;;
            -nc | --no-color)
                no_color=1
            ;;
            -k | --key )
                key_name="$1"
                shift
            ;;
            -a | --ask-vault-pass )
                ask_vault_pass="--ask-vault-pass"
            ;;
            -d | --destroy )
                destroy=1
            ;;
            -y | --yes)
                yes=1
            ;;
            * )
                args+=("$param")
            ;;
        esac
    done

    # Restore positional args
    set -- "${args[@]}"

    # set positionals to vars
    provider="${args[0]}"
    additional_args="${args[@]:1}"
    terraform_yes=$( [[ -z "${yes}" ]] && echo "" || echo "-auto-approve" )

    # Validate required args
    if ! [[ "$provider" =~ ^(oracle|openstack|gcp|wireguard)$ ]]; then
        >&2 echo "Invalid argument 'provider': ${provider:-'not set'}. 
        Must be one of: [oracle, openstack, gcp, wireguard]"
        usage
        exit;
    fi
}

# DESC: Verify the user wants to continue asking (y/n)
# ARGS: $1: Message to display
# OUTS: None
function confirm() {
    local message="$1"
    if [[ -z "${yes}" ]]; then
        read -p "${message}${ta_bold}Continue?${ta_none} ${ta_uscore}[y/N]${ta_none} " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            >&2 echo "Operation aborted by user"
            exit 1
        fi
    fi
}

# DESC: Setup the remote host using Ansible
# ARGS: None
# OUTS: None
function fun_terraform() {
    cd "${script_dir}/Terraform/${provider}"
    if [[ -n "${destroy}" ]]; then
        echo "Start terraform destroy"
        terraform destroy $additional_args $terraform_yes
    else
        echo "Start terraform apply"
        terraform apply $additional_args $terraform_yes
        terraform output -raw private_key > "../../Ansible/${key_name}"
        chmod 600 "../../Ansible/${key_name}"
        uername=$(terraform output -raw username)
        public_ip=$(terraform output -raw public_ip)
        sed -i "s/ansible_host: *[^#]*/ansible_host: ${public_ip} /" ../../Ansible/inventory.yml
        sed -i "s/ansible_user: *[^#]*/ansible_user: ${uername} /" ../../Ansible/inventory.yml
    fi
    cd "${origin_cwd}"
}

# DESC: Use Ansible to install and configure wireguard on the server
# ARGS: None
# OUTS: None
function fun_ansible() {
    confirm "Start wireguard installation. "
    cd "${script_dir}/Ansible"
    ansible-playbook -i inventory.yml --private-key ${key_name} wireguard.yml ${ask_vault_pass} $additional_args
    cd "${origin_cwd}"
}

# DESC: Main control flow
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: None
function main() {
    script_init "$@"
    parse_args "$@"
    if [[ -z "${no_color}" ]]; then
        color_init
    fi

    case "${provider}" in
        openstack | oracle | gcp )
            fun_terraform
        ;;
        wireguard )
            fun_ansible
        ;;
    esac
}

# Invoke main with args if not sourced
if ! (return 0 2> /dev/null); then
    main "$@"
fi
