#!/usr/bin/env bash

kxxx_identity_index_file() {
  printf '%s/.local/state/kxxx/secret-index.tsv\n' "$HOME"
}

kxxx_identity_prepare_index_file() {
  local index_file="${1:-}"
  local index_dir=""

  [[ -n "$index_file" ]] || index_file="$(kxxx_identity_index_file)"
  index_dir="$(dirname "$index_file")"

  mkdir -p "$index_dir" || return 1
  touch "$index_file" || return 1
  chmod 600 "$index_file" 2>/dev/null || true
}

kxxx_identity_create_ref_for_backend() {
  local backend="$1" id="${2:-}"
  local resolved_backend=""

  resolved_backend="$(kxxx_backend_resolve_name "$backend")" || return 1
  kxxx_backend_create_ref "$resolved_backend" "$id"
}

kxxx_identity_create_keychain_ref() {
  kxxx_identity_create_ref_for_backend "darwin-keychain" "${1:-}"
}

kxxx_identity_account_for_ref() {
  kxxx_backend_ref_account "$1"
}

kxxx_identity_parse_binding_descriptor() {
  local descriptor="$1"
  local -n scope_ref="$2"
  local -n repo_ref="$3"
  local -n name_ref="$4"

  scope_ref=""
  repo_ref=""
  name_ref=""

  if [[ "$descriptor" =~ ^env/([A-Za-z_][A-Za-z0-9_]*)$ ]]; then
    scope_ref="global"
    name_ref="${BASH_REMATCH[1]}"
    return 0
  fi

  if [[ "$descriptor" =~ ^app/([^/]+)/([A-Za-z_][A-Za-z0-9_]*)$ ]]; then
    scope_ref="repo"
    repo_ref="${BASH_REMATCH[1]}"
    name_ref="${BASH_REMATCH[2]}"
    return 0
  fi

  return 1
}

kxxx_identity_parse_record_line() {
  local line="$1"
  local -n service_ref="$2"
  local -n secret_ref_ref="$3"
  local -n descriptor_ref="$4"
  local -n binding_scope_ref="$5"
  local -n binding_repo_ref="$6"
  local -n binding_name_ref="$7"
  local rest="$line"
  local i=0
  local -a parts=()

  service_ref=""
  secret_ref_ref=""
  descriptor_ref=""
  binding_scope_ref=""
  binding_repo_ref=""
  binding_name_ref=""

  [[ -n "$line" ]] || return 1

  for ((i = 0; i < 5; i += 1)); do
    [[ "$rest" == *$'\t'* ]] || return 1
    parts+=("${rest%%$'\t'*}")
    rest="${rest#*$'\t'}"
  done
  parts+=("$rest")

  service_ref="${parts[0]}"
  secret_ref_ref="${parts[1]}"
  descriptor_ref="${parts[2]}"
  binding_scope_ref="${parts[3]}"
  binding_repo_ref="${parts[4]}"
  binding_name_ref="${parts[5]}"

  [[ -n "$service_ref" && -n "$secret_ref_ref" && -n "$descriptor_ref" ]]
}

kxxx_identity_find_record() {
  local service="$1" field="$2" needle="$3"
  local -n ref_ref="$4"
  local -n descriptor_ref="$5"
  local -n binding_scope_ref="$6"
  local -n binding_repo_ref="$7"
  local -n binding_name_ref="$8"
  local index_file=""
  local line=""
  local rec_service="" rec_ref="" rec_descriptor="" rec_scope="" rec_repo="" rec_name=""
  local haystack=""

  ref_ref=""
  descriptor_ref=""
  binding_scope_ref=""
  binding_repo_ref=""
  binding_name_ref=""

  index_file="$(kxxx_identity_index_file)"
  [[ -f "$index_file" ]] || return 1

  while IFS= read -r line || [[ -n "$line" ]]; do
    if ! kxxx_identity_parse_record_line "$line" rec_service rec_ref rec_descriptor rec_scope rec_repo rec_name; then
      continue
    fi
    [[ "$rec_service" == "$service" ]] || continue

    case "$field" in
      descriptor)
        haystack="$rec_descriptor"
        ;;
      ref)
        haystack="$rec_ref"
        ;;
      *)
        return 1
        ;;
    esac

    [[ "$haystack" == "$needle" ]] || continue

    ref_ref="$rec_ref"
    descriptor_ref="$rec_descriptor"
    binding_scope_ref="$rec_scope"
    binding_repo_ref="$rec_repo"
    binding_name_ref="$rec_name"
    return 0
  done < "$index_file"

  return 1
}

kxxx_identity_find_record_by_descriptor() {
  kxxx_identity_find_record "$1" "descriptor" "$2" "$3" "$4" "$5" "$6" "$7"
}

kxxx_identity_find_record_by_ref() {
  kxxx_identity_find_record "$1" "ref" "$2" "$3" "$4" "$5" "$6" "$7"
}

kxxx_identity_get_descriptor_ref() {
  local service="$1" descriptor="$2"
  local -n ref_ref="$3"
  local found_ref="" existing_descriptor="" binding_scope="" binding_repo="" binding_name=""

  if ! kxxx_identity_find_record_by_descriptor "$service" "$descriptor" found_ref existing_descriptor binding_scope binding_repo binding_name; then
    return 1
  fi

  ref_ref="$found_ref"
}

kxxx_identity_upsert_record() {
  local service="$1" ref="$2" descriptor="$3" binding_scope="$4" binding_repo="$5" binding_name="$6"
  local index_file="" index_dir="" tmp_file=""
  local line=""
  local rec_service="" rec_ref="" rec_descriptor="" rec_scope="" rec_repo="" rec_name=""

  index_file="$(kxxx_identity_index_file)"
  kxxx_identity_prepare_index_file "$index_file" || return 1
  index_dir="$(dirname "$index_file")"
  tmp_file="$(mktemp "${index_dir}/secret-index.tsv.tmp.XXXXXX")" || return 1

  while IFS= read -r line || [[ -n "$line" ]]; do
    if ! kxxx_identity_parse_record_line "$line" rec_service rec_ref rec_descriptor rec_scope rec_repo rec_name; then
      [[ -n "$line" ]] && printf '%s\n' "$line" >> "$tmp_file"
      continue
    fi

    if [[ "$rec_service" == "$service" && "$rec_descriptor" == "$descriptor" ]]; then
      continue
    fi

    if [[ "$rec_service" == "$service" && "$rec_ref" == "$ref" ]]; then
      continue
    fi

    printf '%s\n' "$line" >> "$tmp_file"
  done < "$index_file"

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$service" \
    "$ref" \
    "$descriptor" \
    "$binding_scope" \
    "$binding_repo" \
    "$binding_name" >> "$tmp_file"

  chmod 600 "$tmp_file" 2>/dev/null || true
  mv "$tmp_file" "$index_file"
}

kxxx_identity_set_descriptor() {
  local service="$1" descriptor="$2" value="$3" backend="${4:-auto}" out_var="${5:-}"
  local ref="" existing_descriptor="" binding_scope="" binding_repo="" binding_name=""
  local resolved_backend="" ref_backend="" ref_impl_backend="" ref_id=""

  resolved_backend="$(kxxx_backend_resolve_cli_name "$backend")" || return 1

  if kxxx_identity_find_record_by_descriptor "$service" "$descriptor" ref existing_descriptor binding_scope binding_repo binding_name; then
    if kxxx_secret_ref_parse "$ref" ref_backend ref_id; then
      ref_impl_backend="$(kxxx_backend_impl_name_for_ref_backend "$ref_backend")" || return 1
      if [[ "$ref_impl_backend" != "$resolved_backend" ]]; then
        ref="$(kxxx_identity_create_ref_for_backend "$resolved_backend")" || return 1
      fi
    else
      ref="$(kxxx_identity_create_ref_for_backend "$resolved_backend")" || return 1
    fi
  fi

  if [[ -z "$ref" ]]; then
    ref="$(kxxx_identity_create_ref_for_backend "$resolved_backend")" || return 1
  fi

  kxxx_backend_set_ref "$service" "$ref" "$value" || return 1
  kxxx_identity_parse_binding_descriptor "$descriptor" binding_scope binding_repo binding_name || true
  kxxx_identity_upsert_record "$service" "$ref" "$descriptor" "$binding_scope" "$binding_repo" "$binding_name" || return 1

  if [[ -n "$out_var" ]]; then
    local -n out_ref="$out_var"
    out_ref="$ref"
  fi
}

kxxx_identity_get_descriptor() {
  local service="$1" descriptor="$2" backend="${3:-auto}"
  local -n value_ref="$4"
  local ref="" existing_descriptor="" binding_scope="" binding_repo="" binding_name=""

  value_ref=""

  if ! kxxx_identity_find_record_by_descriptor "$service" "$descriptor" ref existing_descriptor binding_scope binding_repo binding_name; then
    return 1
  fi

  if ! value_ref="$(kxxx_backend_get_ref "$service" "$ref")"; then
    value_ref=""
    return 2
  fi

  return 0
}

kxxx_identity_has_descriptor() {
  local service="$1" descriptor="$2"
  local ref="" existing_descriptor="" binding_scope="" binding_repo="" binding_name=""

  kxxx_identity_find_record_by_descriptor "$service" "$descriptor" ref existing_descriptor binding_scope binding_repo binding_name >/dev/null 2>&1
}

kxxx_identity_list_descriptors() {
  local service="$1"
  local index_file=""
  local line=""
  local rec_service="" rec_ref="" rec_descriptor="" rec_scope="" rec_repo="" rec_name=""
  declare -A seen_descriptors=()

  index_file="$(kxxx_identity_index_file)"
  [[ -f "$index_file" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    if ! kxxx_identity_parse_record_line "$line" rec_service rec_ref rec_descriptor rec_scope rec_repo rec_name; then
      continue
    fi
    [[ "$rec_service" == "$service" ]] || continue
    [[ -n "$rec_descriptor" ]] || continue
    [[ -n "${seen_descriptors[$rec_descriptor]+x}" ]] && continue
    seen_descriptors["$rec_descriptor"]=1
    printf '%s\n' "$rec_descriptor"
  done < "$index_file"
}

kxxx_identity_account_is_managed_ref() {
  local service="$1" account="$2"
  local index_file="" line=""
  local rec_service="" rec_ref="" rec_descriptor="" rec_scope="" rec_repo="" rec_name=""
  local ref_id=""

  if [[ ! "$account" =~ ^ref/([A-Za-z0-9._-]+)$ ]]; then
    return 1
  fi

  ref_id="${BASH_REMATCH[1]}"
  index_file="$(kxxx_identity_index_file)"
  [[ -f "$index_file" ]] || return 1

  while IFS= read -r line || [[ -n "$line" ]]; do
    if ! kxxx_identity_parse_record_line "$line" rec_service rec_ref rec_descriptor rec_scope rec_repo rec_name; then
      continue
    fi
    [[ "$rec_service" == "$service" ]] || continue
    [[ "$rec_ref" == secretref:v1:*:"$ref_id" ]] || continue
    return 0
  done < "$index_file"

  return 1
}

kxxx_identity_collect_env_map() {
  local service="$1" repo="$2" backend="${3:-auto}"
  local -n env_ref="$4"
  local -n owned_ref="$5"
  local index_file=""
  local line=""
  local rec_service="" rec_ref="" rec_descriptor="" rec_scope="" rec_repo="" rec_name=""
  local value=""

  index_file="$(kxxx_identity_index_file)"
  [[ -f "$index_file" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    if ! kxxx_identity_parse_record_line "$line" rec_service rec_ref rec_descriptor rec_scope rec_repo rec_name; then
      continue
    fi
    [[ "$rec_service" == "$service" ]] || continue
    [[ "$rec_scope" == "global" ]] || continue
    [[ -n "$rec_name" ]] || continue

    owned_ref["global:$rec_name"]=1
    if value="$(kxxx_backend_get_ref "$service" "$rec_ref")"; then
      env_ref["$rec_name"]="$value"
    fi
  done < "$index_file"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if ! kxxx_identity_parse_record_line "$line" rec_service rec_ref rec_descriptor rec_scope rec_repo rec_name; then
      continue
    fi
    [[ "$rec_service" == "$service" ]] || continue
    [[ "$rec_scope" == "repo" ]] || continue
    [[ "$rec_repo" == "$repo" ]] || continue
    [[ -n "$rec_name" ]] || continue

    owned_ref["repo:$rec_repo:$rec_name"]=1
    if value="$(kxxx_backend_get_ref "$service" "$rec_ref")"; then
      env_ref["$rec_name"]="$value"
    fi
  done < "$index_file"
}

kxxx_identity_collect_env_values() {
  local service="$1" repo="$2" backend="${3:-auto}"
  local -n env_ref="$4"
  declare -A owned_bindings=()

  kxxx_identity_collect_env_map "$service" "$repo" "$backend" env_ref owned_bindings
}

kxxx_identity_store_descriptor() {
  kxxx_identity_set_descriptor "$@"
}
