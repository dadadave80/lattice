#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# check-storage-layout.sh
#
# ERC-7201 storage-layout guard for Foundry projects (bash, jq, git, forge, cast).
#
# An ERC-7201 storage struct that is live on any network may only be EXTENDED by appending fields at
# its end: reordering, retyping, shrinking or removing a field, or changing its
# `@custom:storage-location erc7201:<ns>` namespace, silently corrupts the live storage.
#
# HOW IT WORKS
#   1. Every `@custom:storage-location erc7201:<ns>` annotation under --src is paired with the
#      `struct <Name>` that follows it, so the guarded set is complete by construction. The file that
#      declares it must also contain the namespace's derived slot (`cast index-erc7201 <ns>`) as a
#      literal, which ties the namespace to the slot constant the library uses.
#   2. A library's struct is reached only through an assembly slot cast, so solc emits no layout for
#      it; a probe contract imports each real struct and declares a state variable of that type. The
#      probe is compiled on its own, into a temporary directory (the project's out/ and cache/ are left
#      alone), and each guarded struct's layout must carry the AST id of the struct declared in its
#      file: a probe that lays out a copy (a mirror struct, under any name or from any file) or omits
#      a struct fails the check.
#   3. Each struct's members are normalized to `slot offset label type` rows, with solc's volatile
#      numeric AST ids stripped from type names, so the output is stable across recompiles. Every other
#      struct type reachable from a guarded struct gets its own "(nested)" section.
#   4. DRIFT: the normalized layout must equal the committed baseline byte for byte. A reviewed append
#      therefore needs a baseline update (--update) in the same change.
#   5. COMPATIBILITY (--baseline-ref REF): the layout must also be an append-only extension of the
#      baseline committed at REF, a trusted commit (the PR base or a release). A change that edits both
#      the source and the baseline cannot hide an incompatible layout from this comparison. For each
#      section of the old baseline:
#        - the section must still exist, with an identical header (struct name, namespace, slot);
#        - a top-level struct's old rows must be an exact prefix of its new rows (tail appends only);
#        - a nested struct must be identical (an append can change an array stride or a packed parent).
#      --resets FILE names reviewed exceptions for a fresh deployment. Each line is
#      `<StructName> <hash>`, where <hash> identifies the section at REF (the failure output prints the
#      exact line). An entry applies only while REF still holds that exact layout, and an entry that
#      matches REF but waives nothing fails the check, so a reset cannot sit ready for a later change.
#      A baseline from an older Lattice checker that labelled nested structs with their parent's
#      namespace (one namespace on several sections) is read as nested for those sections.
#
# USAGE
#   check-storage-layout.sh --probe <Name|path.sol:Name> --baseline <file> [options]
#     --root <dir>          Foundry project root (default: current directory)
#     --src <dir>           directory scanned for annotations (default: the profile's `src`)
#     --profile <name>      Foundry profile (default: FOUNDRY_PROFILE, else `default`)
#     --baseline-ref <ref>  trusted git ref for the compatibility check (default: drift only)
#     --resets <file>       reviewed fresh-deployment resets (default: none)
#     --update              regenerate the baseline instead of checking it
#   Relative paths resolve against --root. Exit 0 = pass, 1 = layout check failed, 2 = usage or
#   environment error (missing tool, file or ref, failed compile, vacuous probe).
# ---------------------------------------------------------------------------
set -euo pipefail
# Byte-order collation, so `sort` gives the same section order on macOS and on Linux runners.
export LC_ALL=C

die() {
    echo "ERROR: $*" >&2
    exit 2
}

ROOT="."
SRC=""
PROBE=""
BASELINE=""
PROFILE="${FOUNDRY_PROFILE:-default}"
BASE_REF=""
RESETS=""
UPDATE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root | --src | --probe | --baseline | --profile | --baseline-ref | --resets)
            [[ $# -ge 2 ]] || die "$1 needs a value"
            case "$1" in
                --root) ROOT="$2" ;;
                --src) SRC="$2" ;;
                --probe) PROBE="$2" ;;
                --baseline) BASELINE="$2" ;;
                --profile) PROFILE="$2" ;;
                --baseline-ref) BASE_REF="$2" ;;
                --resets) RESETS="$2" ;;
            esac
            shift 2
            ;;
        --update)
            UPDATE=1
            shift
            ;;
        *) die "unknown argument '$1' (see the usage header of $0)" ;;
    esac
done
[[ -n "${PROBE}" ]] || die "--probe is required"
[[ -n "${BASELINE}" ]] || die "--baseline is required"
[[ "${BASELINE}" != /* ]] || die "--baseline must be relative to the project root"

for tool in forge cast jq git; do
    command -v "${tool}" >/dev/null 2>&1 || die "${tool} not found on PATH"
done

[[ -d "${ROOT}" ]] || die "project root '${ROOT}' is not a directory"
cd "${ROOT}"
export FOUNDRY_PROFILE="${PROFILE}"

if [[ -z "${SRC}" ]]; then
    SRC="$(forge config --json 2>/dev/null | jq -r '.src // empty')" || true
    [[ -n "${SRC}" ]] || die "could not read 'src' from 'forge config' (profile ${PROFILE}); pass --src"
fi
[[ -d "${SRC}" ]] || die "source directory '${SRC}' not found under $(pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# --------------------------------------------------------------------------- guarded structs
# One "<Name> <namespace> <file>" line per annotation. The struct must follow within three lines.
grep -rlE --include='*.sol' '@custom:storage-location erc7201:' "${SRC}" | sort >"${TMP}/files" || true
: >"${TMP}/guarded"
annotations=0
while IFS= read -r file; do
    n="$(grep -cE '@custom:storage-location erc7201:' "${file}")"
    annotations=$((annotations + n))
    awk -v f="${file}" '
        match($0, /erc7201:[A-Za-z0-9._]+/) { ns = substr($0, RSTART + 8, RLENGTH - 8); left = 3; next }
        ns != "" && match($0, /^[[:space:]]*struct[[:space:]]+[A-Za-z0-9_]+/) {
            s = substr($0, RSTART, RLENGTH); sub(/^[[:space:]]*struct[[:space:]]+/, "", s)
            print s " " ns " " f; ns = ""; next
        }
        ns != "" && --left == 0 { ns = "" }
    ' "${file}" >>"${TMP}/guarded"
done <"${TMP}/files"
sort -o "${TMP}/guarded" "${TMP}/guarded"
paired="$(wc -l <"${TMP}/guarded" | tr -d ' ')"
[[ "${annotations}" -gt 0 ]] || die "no '@custom:storage-location erc7201:' annotation found under '${SRC}'"
if [[ "${paired}" -ne "${annotations}" ]]; then
    die "found ${annotations} erc7201 annotations under '${SRC}' but paired only ${paired} with a struct; each annotation must sit directly above its 'struct <Name> {' line"
fi
dupes="$(awk '{print $1}' "${TMP}/guarded" | uniq -d)"
[[ -z "${dupes}" ]] || die "several annotated structs share a name, so their layouts can't be told apart: ${dupes}"
dupes="$(awk '{print $2}' "${TMP}/guarded" | sort | uniq -d)"
[[ -z "${dupes}" ]] || die "an erc7201 namespace is declared more than once: ${dupes}"

# --------------------------------------------------------------------------- probe
probe_file="" probe_name="${PROBE}"
if [[ "${PROBE}" == *:* ]]; then
    probe_file="${PROBE%:*}"
    probe_name="${PROBE##*:}"
else
    probe_file="$(grep -rlE --include='*.sol' "^[[:space:]]*(abstract[[:space:]]+)?contract[[:space:]]+${probe_name}([^A-Za-z0-9_]|$)" \
        --exclude-dir=lib --exclude-dir=node_modules --exclude-dir=out --exclude-dir=cache . 2>/dev/null || true)"
    [[ "$(printf '%s' "${probe_file}" | grep -c '')" -eq 1 ]] \
        || die "probe contract '${probe_name}' must be declared in exactly one file; pass --probe <path.sol>:${probe_name}"
fi
# Source paths as solc names them: relative to the project root, without a leading `./`.
relpath() {
    local p="${1#"$(pwd)"/}"
    while [[ "${p}" == ./* ]]; do p="${p#./}"; done
    printf '%s' "${p}"
}
probe_file="$(relpath "${probe_file}")"
[[ -f "${probe_file}" ]] || die "probe source '${probe_file}' not found"

# --------------------------------------------------------------------------- layout generation
generate_layout() {
    # The probe and everything it imports compile once, into this run's own directories, so the
    # project's out/ and cache/ are never read or written. The one build-info file holds both the
    # probe's storage layout and every source's AST, so the struct ids below match the layout's ids.
    if ! forge build "${probe_file}" --out "${TMP}/out" --cache-path "${TMP}/cache" \
        --build-info --build-info-path "${TMP}/build-info" --extra-output storageLayout >"${TMP}/build.log" 2>&1; then
        cat "${TMP}/build.log" >&2
        die "forge build of the probe ${probe_file} failed (profile ${PROFILE})"
    fi
    local bi info
    for bi in "${TMP}/build-info"/*.json; do
        [[ -e "${bi}" ]] || continue
        if jq -e --arg f "${probe_file}" --arg c "${probe_name}" '.output.contracts[$f][$c].storageLayout.types | type == "object"' \
            "${bi}" >/dev/null 2>&1; then
            info="${bi}"
        fi
    done
    [[ -n "${info:-}" ]] || die "no storageLayout for probe '${probe_name}' in ${probe_file}"
    jq -c --arg f "${probe_file}" --arg c "${probe_name}" '.output.contracts[$f][$c].storageLayout' "${info}" >"${TMP}/layout.json"
    # "<source>\t<struct name>\t<AST id>" for every struct declared at file level or inside a contract.
    jq -r '.output.sources | to_entries[] | .key as $s | .value.ast.nodes[]? | (., .nodes[]?)
        | select(type == "object" and .nodeType == "StructDefinition") | "\($s)\t\(.name)\t\(.id)"' "${info}" >"${TMP}/structs"

    # Members of the struct type <key>, one "slot offset label type" row each, with solc's numeric AST
    # ids stripped from type names so the rows are stable across recompiles.
    struct_members() {
        jq -r --arg k "$1" '(.types[$k].members // [])[] | "\(.slot)\t\(.offset)\t\(.label)\t\(.type)"' "${TMP}/layout.json" \
            | sed -E 's/\)[0-9]+/)/g' | sort -n -k1,1 -k2,2
    }
    # "<name> <key>" for every struct type in the probe layout.
    jq -r '.types | keys[] | select(test("^t_struct\\([A-Za-z0-9_]+\\)[0-9]+_storage$"))
        | "\(capture("^t_struct\\((?<n>[A-Za-z0-9_]+)\\)").n) \(.)"' "${TMP}/layout.json" | sort -u >"${TMP}/types"

    # Sections are keyed by struct name, so two distinct structs with one name would merge their rows.
    local clash
    clash="$(awk '{print $1}' "${TMP}/types" | uniq -d)"
    [[ -z "${clash}" ]] || die "several distinct structs share a name in the probe layout, so their layouts can't be told apart: ${clash}"

    local name ns file src slot_root ids id key members found
    while read -r name ns file; do
        slot_root="$(cast index-erc7201 "${ns}" 2>/dev/null)" || die "cast index-erc7201 failed for '${ns}'"
        grep -qiF "${slot_root#0x}" "${file}" \
            || die "${file} declares erc7201:${ns} but does not contain its slot ${slot_root}"
        # Bind the layout to the declaration: the probe's type key must carry the AST id of the struct
        # declared in this file, so a copy (a mirror, imported under any alias from any file) is rejected.
        src="$(relpath "${file}")"
        ids="$(awk -F'\t' -v s="${src}" -v n="${name}" '$1 == s && $2 == n { print $3 }' "${TMP}/structs")"
        [[ -n "${ids}" ]] \
            || die "probe ${probe_file} does not compile ${src}; import {${name}} from it and declare an internal state variable of that type"
        [[ "$(printf '%s\n' "${ids}" | grep -c '')" -eq 1 ]] || die "${src} declares more than one struct named ${name}"
        id="${ids}"
        key="t_struct(${name})${id}_storage"
        echo "### ${name} @ erc7201:${ns} (slot ${slot_root})"
        members="$(struct_members "${key}")"
        if [[ -z "${members}" ]]; then
            found="$(awk -v n="${name}" '$1 == n { sub(/^t_struct\([A-Za-z0-9_]+\)/, "", $2); sub(/_storage$/, "", $2); print $2 }' "${TMP}/types")"
            [[ -z "${found}" ]] \
                || die "probe ${probe_file} lays out a copy of ${name} (AST id ${found}), not the struct declared in ${src} (AST id ${id}); use the real struct"
            die "guarded struct '${name}' produced ZERO member rows (vacuous guard); import ${name} into ${probe_file} and declare it as an internal state variable"
        fi
        echo "${members}"
        echo ""
    done <"${TMP}/guarded"

    # Every other struct type in the probe layout is nested inside a guarded struct.
    while read -r name key; do
        echo "### ${name} (nested)"
        struct_members "${key}"
        echo ""
    done < <(grep -vE "^($(awk '{print $1}' "${TMP}/guarded" | paste -sd '|' -)) " "${TMP}/types" || true)
}

# Command substitution drops the trailing blank line; a failure inside exits with its status (set -e).
CURRENT="$(generate_layout)"
printf '%s\n' "${CURRENT}" >"${TMP}/current"

if [[ "${UPDATE}" -eq 1 ]]; then
    mkdir -p "$(dirname "${BASELINE}")"
    cp "${TMP}/current" "${BASELINE}"
    echo "Baseline written to ${BASELINE} ($(grep -c '^### ' "${BASELINE}") sections)."
    echo "Review the diff: an APPENDED top-level field is upgrade-safe; a reorder, retype, shrink, removal,"
    echo "namespace change or nested-struct change breaks any deployment that already holds this storage."
    exit 0
fi

[[ -f "${BASELINE}" ]] || die "baseline '${BASELINE}' missing; generate it with --update and review it"

status=0

# --------------------------------------------------------------------------- compatibility
# split <file> <dir>: one file per section, named after its struct, holding the section's lines.
split_sections() {
    mkdir -p "$2"
    awk -v d="$2" '
        /^### / { name = $2; out = d "/" name; printf "" > out }
        /^$/ { next }
        out != "" { print >> out }
    ' "$1"
}

if [[ -n "${BASE_REF}" ]]; then
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "--baseline-ref needs a git checkout at '$(pwd)'"
    git rev-parse --verify --quiet "${BASE_REF}^{commit}" >/dev/null \
        || die "baseline ref '${BASE_REF}' is not a commit in this checkout (fetch it first)"
    prefix="$(git rev-parse --show-prefix)"
    git show "${BASE_REF}:${prefix}${BASELINE#./}" >"${TMP}/trusted" 2>/dev/null \
        || die "no baseline at ${BASE_REF}:${prefix}${BASELINE#./}; seed the baseline in an earlier commit, then compare against it"
    split_sections "${TMP}/trusted" "${TMP}/old"
    split_sections "${TMP}/current" "${TMP}/new"
    reset_file=""
    if [[ -n "${RESETS}" && -f "${RESETS}" ]]; then
        reset_file="${RESETS}"
    fi

    # Namespaces on more than one top-level header of the trusted baseline. The current checker refuses
    # a shared namespace, so only an older Lattice checker wrote these: it labelled each nested struct of
    # a namespace with that namespace instead of "(nested)".
    legacy_ns="$(grep -E '^### [A-Za-z0-9_]+ @ erc7201:' "${TMP}/trusted" | awk '{print $4}' | sort | uniq -d || true)"

    : >"${TMP}/compat"
    : >"${TMP}/used"
    for old in "${TMP}/old"/*; do
        [[ -e "${old}" ]] || continue
        name="${old##*/}"
        new="${TMP}/new/${name}"
        hash="$(git hash-object --stdin <"${old}" | cut -c1-12)"
        problem=""
        old_head="$(head -n1 "${old}")"
        nested=0
        [[ "${old_head}" != *"(nested)" ]] || nested=1
        if [[ ! -f "${new}" ]]; then
            problem="removed: the struct is no longer guarded (deleted, renamed or no longer reachable)"
        else
            new_head="$(head -n1 "${new}")"
            if [[ "${old_head}" != "${new_head}" && "${new_head}" == "### ${name} (nested)" && -n "${legacy_ns}" ]] \
                && grep -qxF "$(awk '{print $4}' <<<"${old_head}")" <<<"${legacy_ns}"; then
                echo "NOTE: ${name} is labelled '$(cut -d' ' -f3- <<<"${old_head}")' at ${BASE_REF} by an older checker; compared as a nested struct." >&2
                old_head="${new_head}"
                nested=1
            fi
            if [[ "${old_head}" != "${new_head}" ]]; then
                problem="header changed (namespace, slot or nesting): '${old_head}' -> '${new_head}'"
            else
                old_rows="$(($(wc -l <"${old}") - 1))"
                new_rows="$(($(wc -l <"${new}") - 1))"
                if [[ "${nested}" -eq 1 && "${old_rows}" -ne "${new_rows}" ]]; then
                    problem="nested struct changed size (${old_rows} -> ${new_rows} members); nested structs must stay identical"
                elif [[ "${new_rows}" -lt "${old_rows}" ]]; then
                    problem="members removed (${old_rows} -> ${new_rows})"
                else
                    diff_rows="$(diff <(tail -n +2 "${old}") <(tail -n +2 "${new}" | head -n "${old_rows}") | grep -E '^[<>]' || true)"
                    [[ -z "${diff_rows}" ]] || problem="existing members changed (< ${BASE_REF}, > candidate):"$'\n'"${diff_rows}"
                fi
            fi
        fi
        [[ -n "${problem}" ]] || continue
        if [[ -n "${reset_file}" ]] && grep -qxE "[[:space:]]*${name}[[:space:]]+${hash}[[:space:]]*" "${reset_file}"; then
            echo "${name} ${hash}" >>"${TMP}/used"
            echo "RESET: ${name} is incompatible with ${BASE_REF} and is waived by '${name} ${hash}' in ${reset_file}." >&2
            echo "       Only a fresh deployment may use this layout; no live deployment may be upgraded to it." >&2
            echo "       ${problem}" >&2
            continue
        fi
        {
            echo "${name}: ${problem}"
            echo "  (a reviewed fresh-deployment reset is the line '${name} ${hash}' in the resets file)"
        } >>"${TMP}/compat"
    done
    # An entry that matches REF but waived nothing would otherwise stay armed for a later, unreviewed
    # change to that struct, so it fails. An entry for another layout has no effect on this comparison.
    if [[ -n "${reset_file}" ]]; then
        while read -r rname rhash _; do
            [[ -n "${rname}" && "${rname}" != \#* ]] || continue
            if [[ ! -f "${TMP}/old/${rname}" ]] \
                || [[ "$(git hash-object --stdin <"${TMP}/old/${rname}" | cut -c1-12)" != "${rhash}" ]]; then
                echo "NOTE: reset entry '${rname} ${rhash}' does not match the layout at ${BASE_REF}, so it has no effect here." >&2
            elif ! grep -qxF "${rname} ${rhash}" "${TMP}/used"; then
                {
                    echo "${rname}: unused reset '${rname} ${rhash}': the layout is compatible with ${BASE_REF}, so the entry"
                    echo "  waives nothing and would waive a later change; remove it, or make the change in this pull request"
                } >>"${TMP}/compat"
            fi
        done <"${reset_file}"
    fi
    if [[ -s "${TMP}/compat" ]]; then
        echo "FAIL: ERC-7201 layouts are not an append-only extension of ${BASE_REF}:${prefix}${BASELINE#./}" >&2
        echo "----------------------------------------------------------------------" >&2
        cat "${TMP}/compat" >&2
        echo "----------------------------------------------------------------------" >&2
        echo "Revert the change, or, for a module with no live deployment that will be deployed fresh," >&2
        echo "add the printed reset line to the resets file for review." >&2
        status=1
    else
        echo "OK: ERC-7201 layouts are append-only relative to ${BASE_REF}."
    fi
else
    echo "NOTE: no --baseline-ref, so only drift against the committed baseline is checked; a change that" >&2
    echo "      edits the source and regenerates the baseline together is not compared with a trusted layout." >&2
fi

# --------------------------------------------------------------------------- drift
if diff -u "${BASELINE}" "${TMP}/current" >"${TMP}/drift.diff" 2>&1; then
    echo "OK: ERC-7201 storage layouts match the committed baseline ${BASELINE}."
else
    echo "FAIL: ERC-7201 storage layout drifted from ${BASELINE}." >&2
    echo "----------------------------------------------------------------------" >&2
    cat "${TMP}/drift.diff" >&2
    echo "----------------------------------------------------------------------" >&2
    echo "If you APPENDED a field (safe): re-run with --update and commit the new baseline." >&2
    echo "A reordered, retyped, shrunk or removed field breaks live storage: revert it." >&2
    status=1
fi
exit "${status}"
