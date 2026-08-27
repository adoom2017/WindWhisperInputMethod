#!/bin/bash

WINDWHISPER_INSTALL_TRANSACTION_STATE="idle"

windwhisper_validate_install_transaction_paths() {
    local source_app="$1"
    local installed_app="$2"
    local installing_app="$3"
    local previous_app="$4"

    for path in "$source_app" "$installed_app" "$installing_app" "$previous_app"; do
        if [[ -z "$path" || "$path" == "/" || "$path" == "$HOME" ]]; then
            echo "Refusing unsafe install transaction path: $path" >&2
            return 65
        fi
    done
    if [[ "$source_app" == "$installed_app" \
        || "$source_app" == "$installing_app" \
        || "$source_app" == "$previous_app" \
        || "$installed_app" == "$installing_app" \
        || "$installed_app" == "$previous_app" \
        || "$installing_app" == "$previous_app" ]]; then
        echo "Install transaction paths must be distinct." >&2
        return 65
    fi
    if [[ "$(dirname "$installed_app")" != "$(dirname "$installing_app")" \
        || "$(dirname "$installed_app")" != "$(dirname "$previous_app")" ]]; then
        echo "Installed, staging, and rollback bundles must share one directory." >&2
        return 65
    fi
}

windwhisper_begin_install_transaction() {
    local source_app="$1"
    local installed_app="$2"
    local installing_app="$3"
    local previous_app="$4"

    windwhisper_validate_install_transaction_paths \
        "$source_app" "$installed_app" "$installing_app" "$previous_app" \
        || return
    if [[ ! -d "$source_app" || -e "$installing_app" || -e "$previous_app" ]]; then
        echo "Install transaction preconditions were not met." >&2
        return 65
    fi

    if ! /bin/mv "$source_app" "$installing_app"; then
        WINDWHISPER_INSTALL_TRANSACTION_STATE="idle"
        return 1
    fi
    WINDWHISPER_INSTALL_TRANSACTION_STATE="staged"
    if [[ -e "$installed_app" ]]; then
        if ! /bin/mv "$installed_app" "$previous_app"; then
            return 1
        fi
        WINDWHISPER_INSTALL_TRANSACTION_STATE="previous"
    fi
    if ! /bin/mv "$installing_app" "$installed_app"; then
        return 1
    fi
    WINDWHISPER_INSTALL_TRANSACTION_STATE="swapped"
}

windwhisper_rollback_install_transaction() {
    local source_app="$1"
    local installed_app="$2"
    local installing_app="$3"
    local previous_app="$4"

    windwhisper_validate_install_transaction_paths \
        "$source_app" "$installed_app" "$installing_app" "$previous_app" \
        || return
    /bin/mkdir -p "$(dirname "$source_app")" || return
    case "$WINDWHISPER_INSTALL_TRANSACTION_STATE" in
    idle)
        return 0
        ;;
    staged)
        if [[ -e "$installing_app" ]]; then
            /bin/mv "$installing_app" "$source_app" || return
        fi
        ;;
    previous)
        if [[ -e "$installing_app" ]]; then
            /bin/mv "$installing_app" "$source_app" || return
        fi
        if [[ -e "$previous_app" ]]; then
            /bin/mv "$previous_app" "$installed_app" || return
        fi
        ;;
    swapped)
        if [[ -e "$previous_app" ]]; then
            /bin/mv "$installed_app" "$source_app" || return
            /bin/mv "$previous_app" "$installed_app" || return
        elif [[ -e "$installed_app" ]]; then
            /bin/mv "$installed_app" "$source_app" || return
        fi
        ;;
    *)
        echo "Unknown install transaction state: $WINDWHISPER_INSTALL_TRANSACTION_STATE" >&2
        return 65
        ;;
    esac
    WINDWHISPER_INSTALL_TRANSACTION_STATE="idle"
}

windwhisper_commit_install_transaction() {
    local previous_app="$1"
    if [[ -z "$previous_app" || "$previous_app" == "/" || "$previous_app" == "$HOME" ]]; then
        echo "Refusing unsafe rollback cleanup path: $previous_app" >&2
        return 65
    fi
    if [[ -e "$previous_app" ]]; then
        /bin/rm -rf "$previous_app" || return
    fi
    WINDWHISPER_INSTALL_TRANSACTION_STATE="idle"
}
