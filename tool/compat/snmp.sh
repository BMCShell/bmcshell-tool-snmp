# BMC Shell 2.0 - plugins/snmp.sh

_bmc_snmp_names() { printf '%s\n' snmpget snmpgetnext snmpwalk snmpbulkwalk snmpbulkget snmpset; }

_bmc_snmp_init() {
    unset _BMC_SNMP_COMMUNITY
    _BMC_SNMP_COMMUNITY=''
    export -n _BMC_SNMP_COMMUNITY 2>/dev/null
    _BMC_SNMP_VERSION=2c
    _BMC_SNMP_SNAPSHOT_READY=0
}

# Native and versioned names are all covered by the central registry preflight.
_bmc_snmp_preflight() { return 0; }

_bmc_snmp_activate() {
    local tool function_key alias_key
    local +x function_body='' alias_body=''
    for tool in snmpget snmpgetnext snmpwalk snmpbulkwalk snmpbulkget snmpset; do
        function_key="_BMC_SAVED_${tool^^}_FUNCTION"; alias_key="_BMC_SAVED_${tool^^}_ALIAS"
        function_body=''
        if declare -F "$tool" >/dev/null; then function_body=$(declare -f "$tool") || return; fi
        alias_body=''
        if alias "$tool" &>/dev/null; then alias_body=$(alias "$tool") || return; fi
        export -n "$function_key" "$alias_key" 2>/dev/null
        printf -v "$function_key" '%s' "$function_body"
        printf -v "$alias_key" '%s' "$alias_body"
    done
    _BMC_SNMP_SNAPSHOT_READY=1
    for tool in snmpget snmpgetnext snmpwalk snmpbulkwalk snmpbulkget snmpset; do unalias "$tool" 2>/dev/null || :; done
    if ! _bmc_snmp_install_functions; then
        _bmc_snmp_restore
        _bmc_error '无法安装 SNMP 命令包装，已恢复先前的命令定义。'; return 2
    fi
    _BMC_SNMP_COMMUNITY=''; export -n _BMC_SNMP_COMMUNITY 2>/dev/null
    _BMC_SNMP_VERSION=2c
}

_bmc_snmp_install_functions() {
    function snmpget { _bmc_snmp_wrapper snmpget "$@"; } || return
    function snmpgetnext { _bmc_snmp_wrapper snmpgetnext "$@"; } || return
    function snmpwalk { _bmc_snmp_wrapper snmpwalk "$@"; } || return
    function snmpbulkwalk { _bmc_snmp_wrapper snmpbulkwalk "$@"; } || return
    function snmpbulkget { _bmc_snmp_wrapper snmpbulkget "$@"; } || return
    function snmpset { _bmc_snmp_wrapper snmpset "$@"; }
}

_bmc_snmp_restore() {
    local tool function_key alias_key
    if [[ ${_BMC_SNMP_SNAPSHOT_READY:-0} == 1 ]]; then
        for tool in snmpget snmpgetnext snmpwalk snmpbulkwalk snmpbulkget snmpset; do
            function_key="_BMC_SAVED_${tool^^}_FUNCTION"; alias_key="_BMC_SAVED_${tool^^}_ALIAS"
            unalias "$tool" 2>/dev/null || :
            unset -f "$tool"
            if [[ -n ${!function_key} ]]; then builtin eval -- "${!function_key}"; fi
            if [[ -n ${!alias_key} ]]; then builtin eval -- "${!alias_key}"; fi
            unset "$function_key" "$alias_key"
        done
    fi
    _BMC_SNMP_COMMUNITY=''; export -n _BMC_SNMP_COMMUNITY 2>/dev/null
    _BMC_SNMP_VERSION=2c; _BMC_SNMP_SNAPSHOT_READY=0
}

_bmc_snmp_read_community() {
    local +x community=''
    [[ -r /dev/tty && -w /dev/tty ]] || { _bmc_error '请输入 SNMP 团体名。非交互调用可给查询或写入命令指定 -c。'; return 2; }
    if ! IFS= read -r -s -p '请输入 SNMP 团体名（独立于 BMC 登录密码）：' community </dev/tty; then
        printf '\n' >/dev/tty; return 130
    fi
    printf '\n' >/dev/tty
    [[ -n $community && ${#community} -le 4096 && $community != *[[:cntrl:]]* ]] || {
        _bmc_error '请输入 1 至 4096 个字符的团体名，且不能包含控制字符。'; return 2;
    }
    export -n _BMC_SNMP_COMMUNITY 2>/dev/null
    _BMC_SNMP_COMMUNITY=$community
}

_bmc_snmp_command() {
    _bmc_secret_guard && _bmc_require_active || return
    export -n _BMC_SNMP_COMMUNITY 2>/dev/null
    local action=${1:--s} version=${2:-2c}
    case $action in
        -h|--help) (( $# == 1 )) || return 2; _bmc_tool snmp ;;
        -s|--status)
            (( $# <= 1 )) || { _bmc_error 'SNMP 会话选项无效。请运行 snmp --help 查看用法。'; return 2; }
            printf 'SNMP 目标：%s（UDP/161）\n默认版本：%s\n会话团体名：%s\n' "$_BMC_IP" "${_BMC_SNMP_VERSION:-2c}" "$(if [[ -n ${_BMC_SNMP_COMMUNITY-} ]]; then printf '已配置'; else printf '未配置'; fi)"
            ;;
        -c|--configure)
            (( $# <= 2 )) && [[ $version == 1 || $version == 2c ]] || { _bmc_error 'snmp -c 仅接受版本 1 或 2c。SNMPv3 的认证参数需在每次调用时传入。'; return 2; }
            _bmc_snmp_read_community || return
            _BMC_SNMP_VERSION=$version
            printf '已配置 SNMPv%s 团体名，目标为 %s，仅在当前 BMC 会话中生效。\n' "$version" "$_BMC_IP"
            ;;
        -r|--clear)
            (( $# == 1 )) || { _bmc_error 'snmp -r 无需附加参数。'; return 2; }
            _BMC_SNMP_COMMUNITY=''; _BMC_SNMP_VERSION=2c
            printf '已清除当前会话的 SNMP 团体名，默认版本恢复为 2c。\n'
            ;;
        *) _bmc_error 'SNMP 会话选项无效。请运行 snmp --help 查看用法。'; return 2 ;;
    esac
}

_bmc_snmp_oid_valid() {
    # Numeric OIDs and textual MIB names can resemble hostnames. The explicit
    # current AGENT is always inserted before them, so operands cannot retarget.
    [[ $1 =~ ^\.?[012](\.[0-9]+)*$ ]] ||
        [[ $1 =~ ^\.?[A-Za-z_] && $1 != *[[:cntrl:]]* && $1 != *'/'* ]]
}

_bmc_snmp_wrapper() {
    _bmc_secret_guard && _bmc_require_active || return
    export -n _BMC_SNMP_COMMUNITY 2>/dev/null
    local tool=$1 version=${_BMC_SNMP_VERSION:-2c} have_community=0 option i store proxy_address executable
    local +x community='' value=''
    local -a opts=() native=() operands=()
    shift
    case $tool in snmpget|snmpgetnext|snmpwalk|snmpbulkwalk|snmpbulkget|snmpset) ;; *) return 2;; esac
    type -P "$tool" >/dev/null 2>&1 || { _bmc_error "找不到 $tool。请运行 bmc doctor -d 查看安装提示。"; return 69; }
    if (( $# == 1 )); then
        case $1 in -h|--help|-H|-V|--version) _bmc_show_command command "$tool" "$1"; command "$tool" "$1"; return $?;; esac
    fi
    while (( $# )); do
        case $1 in
            --) shift; break ;;
            -v|-c)
                (( $# >= 2 )) || { _bmc_error "SNMP 选项 $1 缺少值。"; return 2; }
                option=$1; value=$2; shift 2
                if [[ $option == -v ]]; then version=$value; else community=$value; have_community=1; fi
                ;;
            -v?*) version=${1#-v}; shift ;;
            -c?*) community=${1#-c}; have_community=1; shift ;;
            -d) native+=("$1"); shift ;;
            -CE|-Is|-IS)
                (( $# >= 2 )) || { _bmc_error "SNMP 扩展选项 $1 缺少参数。"; return 2; }
                native+=("$1" "$2"); shift 2
                ;;
            -C|-I)
                (( $# >= 2 )) || { _bmc_error "SNMP 选项 $1 缺少值。"; return 2; }
                option=$1; value=$2
                if [[ $option == -C && $value == E || $option == -I && ( $value == s || $value == S ) ]]; then
                    (( $# >= 3 )) || { _bmc_error "SNMP 扩展选项 $1 缺少参数。"; return 2; }
                    native+=("$1" "$2" "$3"); shift 3
                elif [[ $option == -C && $value == *E* || $option == -I && ( $value == *s* || $value == *S* ) ]]; then
                    _bmc_error '请将 -CE、-Is 或 -IS 与其附加参数分开书写。'; return 2
                else native+=("$1" "$2"); shift 2; fi
                ;;
            -r|-t|-m|-M|-n|-u|-l|-a|-A|-x|-X|-e|-E|-Z|-D|-O|-P|-3m|-3M|-3k|-3K)
                (( $# >= 2 )) || { _bmc_error "SNMP 选项 $1 缺少值。"; return 2; }
                native+=("$1" "$2"); shift 2
                ;;
            -C?*|-I?*)
                value=${1:2}
                if [[ $1 == -C* && $value == *E* || $1 == -I* && ( $value == *s* || $value == *S* ) ]]; then
                    _bmc_error '请将 -CE、-Is 或 -IS 与其附加参数分开书写。'; return 2
                fi
                native+=("$1"); shift
                ;;
            -r?*|-t?*|-m?*|-M?*|-n?*|-u?*|-l?*|-a?*|-A?*|-x?*|-X?*|-e?*|-E?*|-Z?*|-D?*|-O?*|-P?*|-3m?*|-3M?*|-3k?*|-3K?*)
                native+=("$1"); shift
                ;;
            -*) _bmc_error '此工具不支持该 SNMP 选项写法。需要独立连接时可使用 command 调用原生 SNMP 命令。'; return 2 ;;
            *) break ;;
        esac
    done
    version=${_bmc_forced_version:-$version}
    [[ $version == 1 || $version == 2c || $version == 3 ]] || { _bmc_error 'SNMP 版本必须为 1、2c 或 3。'; return 2; }
    operands=("$@")
    if [[ $tool == snmpset ]]; then
        (( $# >= 3 && $# % 3 == 0 )) || { _bmc_error '请为 snmpset 提供一组或多组 <OID> <类型> <值>，目标 IP 使用当前会话。'; return 2; }
        for ((i=0; i<${#operands[@]}; i+=3)); do
            _bmc_snmp_oid_valid "${operands[i]}" && [[ ${operands[i+1]} =~ ^[iusxdnotabUIFD=]$ ]] || {
                _bmc_error 'SNMP 写入的 OID 或类型无效。请使用 <OID> <类型> <值> 格式，目标 IP 使用当前会话。'; return 2;
            }
        done
    else
        if [[ $tool != snmpwalk && $tool != snmpbulkwalk ]] && (( $# == 0 )); then
            _bmc_error '请提供至少一个 OID，目标 IP 使用当前会话。'; return 2
        fi
        for value in "$@"; do _bmc_snmp_oid_valid "$value" || { _bmc_error 'OID 无效或传入了额外的目标地址。目标 IP 使用当前会话。'; return 2; }; done
    fi
    opts=(-v "$version")
    # Keep read and write defaults separate and outside the release.
    if [[ $version == 2c ]] && (( have_community == 0 )); then
        store=$(_bmc_config_dir)/credentials/snmp-v2c-read
        [[ $tool == snmpset ]] && store=$(_bmc_config_dir)/credentials/snmp-v2c-write
        if [[ ! -r $store ]]; then _bmc_error "请在 $store 中配置 SNMPv2c 团体名，或使用 -c 指定本次调用的团体名。"; return 69; fi
        IFS= read -r community < "$store" || [[ -n $community ]] || return 2
        community=${community%$'\r'}
        have_community=1
    fi
    if [[ $version != 3 ]]; then
        if (( have_community == 0 )); then
            if [[ -z ${_BMC_SNMP_COMMUNITY-} ]]; then _bmc_snmp_read_community || return; fi
            community=$_BMC_SNMP_COMMUNITY
        fi
        [[ -n $community && ${#community} -le 4096 && $community != *[[:cntrl:]]* ]] || {
            _bmc_error 'SNMP 团体名无效。请输入 1 至 4096 个字符，且不能包含控制字符。'; return 2;
        }
        opts+=(-c "$community")
    elif (( have_community )); then _bmc_error '-c 适用于 SNMPv1 和 v2c。请使用 SNMPv3 的原生认证选项。'; return 2; fi
    opts+=("${native[@]}")
    # -- ends option parsing before the AGENT and protects values beginning '-'.
    proxy_address=$(_bmcshell_bridge proxy-address) || return
    if [[ -n $proxy_address ]]; then
        executable=$(type -P "$tool") && executable=$(_bmc_winpath "$executable") || return
        _bmcshell_bridge proxy-run snmp "$_BMC_IP" "$executable" "$((${#opts[@]} + 1))" "${opts[@]}" -- "${operands[@]}"
        return
    fi
    _bmc_show_command command "$tool" "${opts[@]}" -- "$_BMC_IP" "${operands[@]}"
    command "$tool" "${opts[@]}" -- "$_BMC_IP" "${operands[@]}"
}

_bmc_snmp_versioned() {
    local version=$1 operation=$2; shift 2
    local _bmc_forced_version=$version
    _bmc_snmp_wrapper "snmp$operation" "$@"
}

function _bmc_tool_snmp2get { _bmc_snmp_versioned 2c get "$@"; }

function _bmc_tool_snmp2getnext { _bmc_snmp_versioned 2c getnext "$@"; }

function _bmc_tool_snmp2walk { _bmc_snmp_versioned 2c walk "$@"; }

function _bmc_tool_snmp2bulkwalk { _bmc_snmp_versioned 2c bulkwalk "$@"; }

function _bmc_tool_snmp2bulkget { _bmc_snmp_versioned 2c bulkget "$@"; }

function _bmc_tool_snmp2set { _bmc_snmp_versioned 2c set "$@"; }

function _bmc_tool_snmp3get { _bmc_snmp_versioned 3 get "$@"; }

function _bmc_tool_snmp3getnext { _bmc_snmp_versioned 3 getnext "$@"; }

function _bmc_tool_snmp3walk { _bmc_snmp_versioned 3 walk "$@"; }

function _bmc_tool_snmp3bulkwalk { _bmc_snmp_versioned 3 bulkwalk "$@"; }

function _bmc_tool_snmp3bulkget { _bmc_snmp_versioned 3 bulkget "$@"; }

function _bmc_tool_snmp3set { _bmc_snmp_versioned 3 set "$@"; }


_bmc_snmp_switched() {
    _BMC_SNMP_COMMUNITY=''; export -n _BMC_SNMP_COMMUNITY 2>/dev/null
    _BMC_SNMP_VERSION=2c
}
_bmc_snmp_init
_bmc_register_plugin snmp 'SNMPv1/v2c/v3 命令' _bmc_snmp_preflight _bmc_snmp_activate _bmc_snmp_restore _bmc_snmp_switched
_bmc_register_tool snmp _bmc_snmp_command 'SNMP 会话配置；bmc tool snmp' || return

_bmc_register_tool snmp2get _bmc_tool_snmp2get 'snmp 工具：bmc tool snmp2get' || return
_bmc_register_tool snmp2getnext _bmc_tool_snmp2getnext 'snmp 工具：bmc tool snmp2get' || return
_bmc_register_tool snmp2walk _bmc_tool_snmp2walk 'snmp 工具：bmc tool snmp2get' || return
_bmc_register_tool snmp2bulkwalk _bmc_tool_snmp2bulkwalk 'snmp 工具：bmc tool snmp2get' || return
_bmc_register_tool snmp2bulkget _bmc_tool_snmp2bulkget 'snmp 工具：bmc tool snmp2get' || return
_bmc_register_tool snmp2set _bmc_tool_snmp2set 'snmp 工具：bmc tool snmp2get' || return
_bmc_register_tool snmp3get _bmc_tool_snmp3get 'snmp 工具：bmc tool snmp2get' || return
_bmc_register_tool snmp3getnext _bmc_tool_snmp3getnext 'snmp 工具：bmc tool snmp2get' || return
_bmc_register_tool snmp3walk _bmc_tool_snmp3walk 'snmp 工具：bmc tool snmp2get' || return
_bmc_register_tool snmp3bulkwalk _bmc_tool_snmp3bulkwalk 'snmp 工具：bmc tool snmp2get' || return
_bmc_register_tool snmp3bulkget _bmc_tool_snmp3bulkget 'snmp 工具：bmc tool snmp2get' || return
_bmc_register_tool snmp3set _bmc_tool_snmp3set 'snmp 工具：bmc tool snmp2get' || return

_bmc_tool_snmpget() { _bmc_snmp_wrapper snmpget "$@"; }
_bmc_register_tool snmpget _bmc_tool_snmpget '原生 SNMP 包装；bmc tool snmp2get' plugin || return

_bmc_tool_snmpgetnext() { _bmc_snmp_wrapper snmpgetnext "$@"; }
_bmc_register_tool snmpgetnext _bmc_tool_snmpgetnext '原生 SNMP 包装；bmc tool snmp2get' plugin || return

_bmc_tool_snmpwalk() { _bmc_snmp_wrapper snmpwalk "$@"; }
_bmc_register_tool snmpwalk _bmc_tool_snmpwalk '原生 SNMP 包装；bmc tool snmp2get' plugin || return

_bmc_tool_snmpbulkwalk() { _bmc_snmp_wrapper snmpbulkwalk "$@"; }
_bmc_register_tool snmpbulkwalk _bmc_tool_snmpbulkwalk '原生 SNMP 包装；bmc tool snmp2get' plugin || return

_bmc_tool_snmpbulkget() { _bmc_snmp_wrapper snmpbulkget "$@"; }
_bmc_register_tool snmpbulkget _bmc_tool_snmpbulkget '原生 SNMP 包装；bmc tool snmp2get' plugin || return

_bmc_tool_snmpset() { _bmc_snmp_wrapper snmpset "$@"; }
_bmc_register_tool snmpset _bmc_tool_snmpset '原生 SNMP 包装；bmc tool snmp2get' plugin || return
