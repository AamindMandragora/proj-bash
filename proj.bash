#!/usr/bin/env bash
# ── proj — lightweight project manager ────────────────────────────────
#
# Install:
#   git clone https://github.com/advay168/proj ~/.proj
#   echo '[ -f ~/.proj/proj.bash ] && source ~/.proj/proj.bash' >> ~/.bashrc
#
# File format (~/.projects):
#   name:::path:::host:::hook:::tags
#   logana:::/c/Users/advay/logana:::local:::source .env:::personal,cpp
#   cs341:::/home/advay/cs341:::ews::::::school
#
# Commands:
#   proj add <name> <path> [host]    register a project
#   proj del <name>                  remove a project
#   proj rename <old> <new>          rename a project
#   proj path <name> <new-path>      change project path
#   proj cd <name>                   cd into project (runs hook)
#   proj code <name>                 open in VS Code
#   proj cursor <name>               open in Cursor
#   proj hook <name> <command>       set a hook to run on cd
#   proj unhook <name>               remove a project's hook
#   proj tag <name> <tag>            add a tag
#   proj untag <name> <tag>          remove a tag
#   proj info <name>                 show project details + git status
#   proj ls [tag]                    fuzzy pick, optionally filtered by tag
#   proj status [tag]                git status dashboard for all projects
#   proj edit                        open config in $EDITOR
#   proj export [file]               export config to file (default: stdout)
#   proj import <file|->             import config from file or stdin

PROJ_FILE="${PROJ_FILE:-$HOME/.projects}"
PROJ_DELIM=":::"
touch "$PROJ_FILE"

# ── helpers ──────────────────────────────────────────────────────────

__proj_colors() {
  _green="\033[38;5;121m"
  _blue="\033[38;5;39m"
  _dim="\033[2m"
  _bold="\033[1m"
  _red="\033[38;5;204m"
  _yellow="\033[38;5;228m"
  _cyan="\033[38;5;117m"
  _magenta="\033[38;5;183m"
  _reset="\033[0m"
}

__proj_get() {
  grep "^$1${PROJ_DELIM}" "$PROJ_FILE" | head -1
}

__proj_field() {
  echo "$1" | awk -F':::' "{print \$$2}"
}

__proj_hook() {
  echo "$1" | awk -F':::' '{print $4}'
}

__proj_tags() {
  echo "$1" | awk -F':::' '{print $5}'
}

__proj_set_line() {
  local name="$1" path="$2" host="$3" hook="$4" tags="$5"
  echo "${name}${PROJ_DELIM}${path}${PROJ_DELIM}${host}${PROJ_DELIM}${hook}${PROJ_DELIM}${tags}"
}

__proj_replace() {
  local name="$1" newline="$2"
  local tmpfile
  tmpfile=$(mktemp)
  while IFS= read -r line; do
    if [[ "$line" == "$name${PROJ_DELIM}"* ]]; then
      echo "$newline"
    else
      echo "$line"
    fi
  done < "$PROJ_FILE" > "$tmpfile"
  mv "$tmpfile" "$PROJ_FILE"
}

__proj_names() {
  local tag="$1"
  if [ -n "$tag" ]; then
    awk -F':::' -v t="$tag" '{
      n=split($5,tags,",")
      for(i=1;i<=n;i++) if(tags[i]==t) { print $1; break }
    }' "$PROJ_FILE" | sort -f
  else
    awk -F':::' '{print $1}' "$PROJ_FILE" | sort -f
  fi
}

__proj_git_status() {
  local path="$1"
  [ ! -d "$path/.git" ] && echo "—" && return

  local branch dirty ahead behind age summary

  branch=$(git -C "$path" symbolic-ref --short HEAD 2>/dev/null) || branch="detached"

  dirty=""
  git -C "$path" diff --quiet 2>/dev/null || dirty="*"
  git -C "$path" diff --cached --quiet 2>/dev/null || dirty="${dirty}+"

  ahead=$(git -C "$path" rev-list --count @{u}..HEAD 2>/dev/null)
  behind=$(git -C "$path" rev-list --count HEAD..@{u} 2>/dev/null)

  local last_epoch now_epoch delta
  last_epoch=$(git -C "$path" log -1 --format=%ct 2>/dev/null)
  if [ -n "$last_epoch" ]; then
    now_epoch=$(date +%s)
    delta=$(( now_epoch - last_epoch ))
    if (( delta < 60 )); then
      age="just now"
    elif (( delta < 3600 )); then
      age="$(( delta / 60 ))m ago"
    elif (( delta < 86400 )); then
      age="$(( delta / 3600 ))h ago"
    elif (( delta < 604800 )); then
      age="$(( delta / 86400 ))d ago"
    else
      age="$(( delta / 604800 ))w ago"
    fi
  fi

  summary="${branch}${dirty}"
  [ -n "$ahead" ] && (( ahead > 0 )) && summary="${summary} ↑${ahead}"
  [ -n "$behind" ] && (( behind > 0 )) && summary="${summary} ↓${behind}"
  [ -n "$age" ] && summary="${summary} (${age})"

  echo "$summary"
}

__proj_preview_by_name() {
  local name="$1"
  local projfile="${PROJ_FILE:-$HOME/.projects}"
  local line
  line=$(grep "^${name}:::" "$projfile" | head -1)
  [ -z "$line" ] && echo "not found: $name" && return

  local path host hook tags
  path=$(echo "$line" | awk -F':::' '{print $2}')
  host=$(echo "$line" | awk -F':::' '{print $3}')
  hook=$(echo "$line" | awk -F':::' '{print $4}')
  tags=$(echo "$line" | awk -F':::' '{print $5}')

  echo "╭─ $name"
  echo "│"
  echo "│  path: $path"
  echo "│  host: $host"

  if [ -n "$hook" ]; then
    echo "│  hook: $hook"
  fi

  if [ -n "$tags" ]; then
    echo "│  tags: $tags"
  fi

  echo "│"

  if [ "$host" = "local" ] && [ -d "$path/.git" ]; then
    local branch dirty ahead behind

    branch=$(git -C "$path" symbolic-ref --short HEAD 2>/dev/null) || branch="detached"
    dirty=""
    git -C "$path" diff --quiet 2>/dev/null || dirty=" (dirty)"
    git -C "$path" diff --cached --quiet 2>/dev/null || dirty="${dirty} (staged)"

    ahead=$(git -C "$path" rev-list --count @{u}..HEAD 2>/dev/null)
    behind=$(git -C "$path" rev-list --count HEAD..@{u} 2>/dev/null)

    echo "│  branch: $branch$dirty"
    [ -n "$ahead" ] && (( ahead > 0 )) && echo "│  ahead:  $ahead commits"
    [ -n "$behind" ] && (( behind > 0 )) && echo "│  behind: $behind commits"

    echo "│"
    echo "│  recent commits:"

    git -C "$path" log --oneline --no-decorate -5 2>/dev/null | while IFS= read -r logline; do
      echo "│    $logline"
    done
  elif [ "$host" != "local" ]; then
    echo "│  (remote — no git preview)"
  else
    echo "│  (not a git repo)"
  fi

  echo "│"
  echo "╰─"
}
export -f __proj_preview_by_name
export PROJ_FILE PROJ_DELIM

# ── main ─────────────────────────────────────────────────────────────

function proj() {
  __proj_colors

  case "$1" in
    add)
      if [ -z "$3" ]; then
        echo -e "${_dim}usage:${_reset} proj add ${_blue}<name>${_reset} ${_green}<path>${_reset} ${_dim}[ssh-host]${_reset}"
        return 1
      fi
      if [ -n "$(__proj_get "$2")" ]; then
        echo -e "${_red}✗${_reset} already exists: ${_bold}$2${_reset}"
        return 1
      fi
      local host="${4:-local}"
      echo "$2${PROJ_DELIM}$3${PROJ_DELIM}${host}${PROJ_DELIM}${PROJ_DELIM}" >> "$PROJ_FILE"
      echo -e "${_green}✓${_reset} added ${_bold}$2${_reset} ${_dim}→${_reset} ${host:+${_yellow}${host}${_reset}:}${_blue}$3${_reset}"
      ;;

    rename)
      if [ -z "$3" ]; then
        echo -e "${_dim}usage:${_reset} proj rename ${_blue}<old>${_reset} ${_green}<new>${_reset}"
        return 1
      fi
      if [ -z "$(__proj_get "$2")" ]; then
        echo -e "${_red}✗${_reset} not found: ${_bold}$2${_reset}"
        return 1
      fi
      if [ -n "$(__proj_get "$3")" ]; then
        echo -e "${_red}✗${_reset} already exists: ${_bold}$3${_reset}"
        return 1
      fi
      sed -i "s/^$2${PROJ_DELIM}/$3${PROJ_DELIM}/" "$PROJ_FILE"
      echo -e "${_green}✓${_reset} renamed ${_bold}$2${_reset} ${_dim}→${_reset} ${_bold}$3${_reset}"
      ;;

    path)
      if [ -z "$3" ]; then
        echo -e "${_dim}usage:${_reset} proj path ${_blue}<name>${_reset} ${_green}<new-path>${_reset}"
        return 1
      fi
      local entry=$(__proj_get "$2")
      if [ -z "$entry" ]; then
        echo -e "${_red}✗${_reset} not found: ${_bold}$2${_reset}"
        return 1
      fi
      local host=$(__proj_field "$entry" 3)
      local hook=$(__proj_hook "$entry")
      local tags=$(__proj_tags "$entry")
      __proj_replace "$2" "$(__proj_set_line "$2" "$3" "$host" "$hook" "$tags")"
      echo -e "${_green}✓${_reset} path updated for ${_bold}$2${_reset}: ${_blue}$3${_reset}"
      ;;

    del)
      if [ -n "$(__proj_get "$2")" ]; then
        sed -i "/^$2${PROJ_DELIM}/d" "$PROJ_FILE"
        echo -e "${_green}✓${_reset} removed ${_bold}$2${_reset}"
      else
        echo -e "${_red}✗${_reset} not found: ${_bold}$2${_reset}"
      fi
      ;;

    hook)
      if [ -z "$3" ]; then
        echo -e "${_dim}usage:${_reset} proj hook ${_blue}<name>${_reset} ${_green}<command>${_reset}"
        echo -e "${_dim}  e.g.${_reset} proj hook logana ${_cyan}\"source .env && export BUILD=debug\"${_reset}"
        return 1
      fi
      local entry=$(__proj_get "$2")
      if [ -z "$entry" ]; then
        echo -e "${_red}✗${_reset} not found: ${_bold}$2${_reset}"
        return 1
      fi
      local path=$(__proj_field "$entry" 2)
      local host=$(__proj_field "$entry" 3)
      local tags=$(__proj_tags "$entry")
      local hook="${*:3}"
      __proj_replace "$2" "$(__proj_set_line "$2" "$path" "$host" "$hook" "$tags")"
      echo -e "${_green}✓${_reset} hook set for ${_bold}$2${_reset}: ${_cyan}$hook${_reset}"
      ;;

    unhook)
      if [ -z "$2" ]; then
        echo -e "${_dim}usage:${_reset} proj unhook ${_blue}<name>${_reset}"
        return 1
      fi
      local entry=$(__proj_get "$2")
      if [ -z "$entry" ]; then
        echo -e "${_red}✗${_reset} not found: ${_bold}$2${_reset}"
        return 1
      fi
      local path=$(__proj_field "$entry" 2)
      local host=$(__proj_field "$entry" 3)
      local tags=$(__proj_tags "$entry")
      __proj_replace "$2" "$(__proj_set_line "$2" "$path" "$host" "" "$tags")"
      echo -e "${_green}✓${_reset} hook removed for ${_bold}$2${_reset}"
      ;;

    tag)
      if [ -z "$3" ]; then
        echo -e "${_dim}usage:${_reset} proj tag ${_blue}<name>${_reset} ${_magenta}<tag>${_reset}"
        return 1
      fi
      local entry=$(__proj_get "$2")
      if [ -z "$entry" ]; then
        echo -e "${_red}✗${_reset} not found: ${_bold}$2${_reset}"
        return 1
      fi
      local path=$(__proj_field "$entry" 2)
      local host=$(__proj_field "$entry" 3)
      local hook=$(__proj_hook "$entry")
      local tags=$(__proj_tags "$entry")
      if [[ ",$tags," == *",$3,"* ]]; then
        echo -e "${_dim}already tagged:${_reset} ${_magenta}$3${_reset}"
        return 0
      fi
      if [ -n "$tags" ]; then
        tags="${tags},$3"
      else
        tags="$3"
      fi
      __proj_replace "$2" "$(__proj_set_line "$2" "$path" "$host" "$hook" "$tags")"
      echo -e "${_green}✓${_reset} tagged ${_bold}$2${_reset} +${_magenta}$3${_reset}"
      ;;

    untag)
      if [ -z "$3" ]; then
        echo -e "${_dim}usage:${_reset} proj untag ${_blue}<name>${_reset} ${_magenta}<tag>${_reset}"
        return 1
      fi
      local entry=$(__proj_get "$2")
      if [ -z "$entry" ]; then
        echo -e "${_red}✗${_reset} not found: ${_bold}$2${_reset}"
        return 1
      fi
      local path=$(__proj_field "$entry" 2)
      local host=$(__proj_field "$entry" 3)
      local hook=$(__proj_hook "$entry")
      local tags=$(__proj_tags "$entry")
      tags=$(echo "$tags" | awk -F',' -v t="$3" '{
        out=""
        for(i=1;i<=NF;i++) {
          if($i != t) out = (out ? out "," : "") $i
        }
        print out
      }')
      __proj_replace "$2" "$(__proj_set_line "$2" "$path" "$host" "$hook" "$tags")"
      echo -e "${_green}✓${_reset} untagged ${_bold}$2${_reset} -${_magenta}$3${_reset}"
      ;;

    ls)
      [ ! -s "$PROJ_FILE" ] && echo -e "${_dim}no projects${_reset}" && return

      local tag_filter="$2"
      local names
      names=$(__proj_names "$tag_filter")

      if [ -z "$names" ]; then
        echo -e "${_dim}no projects with tag${_reset} ${_magenta}$tag_filter${_reset}"
        return
      fi

      local out
      out=$(echo "$names" | fzf \
        --prompt="proj> " \
        --header="Enter=cd | Ctrl-O=code | Ctrl-U=cursor" \
        --expect=ctrl-o,ctrl-u \
        --preview='bash -c "__proj_preview_by_name {}"' \
        --preview-window=right:60%)
      local key=$(head -1 <<< "$out")
      local selected=$(sed -n '2p' <<< "$out")
      [ -z "$selected" ] && return
      if [ "$key" = "ctrl-o" ]; then
        proj code "$selected"
      elif [ "$key" = "ctrl-u" ]; then
        proj cursor "$selected"
      else
        proj cd "$selected"
      fi
      ;;

    status)
      [ ! -s "$PROJ_FILE" ] && echo -e "${_dim}no projects${_reset}" && return

      local tag_filter="$2"
      local names
      names=$(__proj_names "$tag_filter")

      if [ -z "$names" ]; then
        echo -e "${_dim}no projects with tag${_reset} ${_magenta}$tag_filter${_reset}"
        return
      fi

      echo ""

      local maxname=4 maxbranch=6
      while IFS= read -r name; do
        (( ${#name} > maxname )) && maxname=${#name}
        local entry=$(__proj_get "$name")
        local path=$(__proj_field "$entry" 2)
        local host=$(__proj_field "$entry" 3)
        if [ "$host" = "local" ] && [ -d "$path/.git" ]; then
          local b
          b=$(git -C "$path" symbolic-ref --short HEAD 2>/dev/null) || b="detached"
          (( ${#b} > maxbranch )) && maxbranch=${#b}
        fi
      done <<< "$names"

      echo -e "  ${_dim}$(printf "%-${maxname}s  %-${maxbranch}s  %-5s  %-5s  %s" "NAME" "BRANCH" "DIRTY" "SYNC" "LAST COMMIT")${_reset}"
      echo -e "  ${_dim}$(printf "%-${maxname}s  %-${maxbranch}s  %-5s  %-5s  %s" \
        "$(printf '%0.s─' $(seq 1 $maxname))" \
        "$(printf '%0.s─' $(seq 1 $maxbranch))" \
        "─────" "─────" "───────────")${_reset}"

      while IFS= read -r name; do
        local entry=$(__proj_get "$name")
        local path=$(__proj_field "$entry" 2)
        local host=$(__proj_field "$entry" 3)

        local pname pbranch pdirty psync page

        pname=$(printf "%-${maxname}s" "$name")
        pname="${_bold}${pname}${_reset}"

        if [ "$host" != "local" ]; then
          pbranch="${_yellow}$(printf "%-${maxbranch}s" "remote")${_reset}"
          pdirty="${_dim}$(printf "%-5s" "-")${_reset}"
          psync="${_dim}$(printf "%-5s" "-")${_reset}"
          page="${_dim}${host}${_reset}"
        elif [ ! -d "$path/.git" ]; then
          pbranch="${_dim}$(printf "%-${maxbranch}s" "-")${_reset}"
          pdirty="${_dim}$(printf "%-5s" "-")${_reset}"
          psync="${_dim}$(printf "%-5s" "-")${_reset}"
          page="${_dim}not a git repo${_reset}"
        else
          local branch
          branch=$(git -C "$path" symbolic-ref --short HEAD 2>/dev/null) || branch="detached"
          pbranch="${_blue}$(printf "%-${maxbranch}s" "$branch")${_reset}"

          if ! git -C "$path" diff --quiet 2>/dev/null || ! git -C "$path" diff --cached --quiet 2>/dev/null; then
            pdirty="${_red}$(printf "%-5s" "yes")${_reset}"
          else
            pdirty="${_green}$(printf "%-5s" "no")${_reset}"
          fi

          local ahead behind
          ahead=$(git -C "$path" rev-list --count @{u}..HEAD 2>/dev/null || echo "0")
          behind=$(git -C "$path" rev-list --count HEAD..@{u} 2>/dev/null || echo "0")
          if (( ahead > 0 && behind > 0 )); then
            psync="${_yellow}$(printf "%-5s" "+${ahead}-${behind}")${_reset}"
          elif (( ahead > 0 )); then
            psync="${_cyan}$(printf "%-5s" "+${ahead}")${_reset}"
          elif (( behind > 0 )); then
            psync="${_red}$(printf "%-5s" "-${behind}")${_reset}"
          else
            psync="${_dim}$(printf "%-5s" "-")${_reset}"
          fi

          local last_epoch now_epoch delta age=""
          last_epoch=$(git -C "$path" log -1 --format=%ct 2>/dev/null)
          if [ -n "$last_epoch" ]; then
            now_epoch=$(date +%s)
            delta=$(( now_epoch - last_epoch ))
            if (( delta < 60 )); then age="just now"
            elif (( delta < 3600 )); then age="$(( delta / 60 ))m ago"
            elif (( delta < 86400 )); then age="$(( delta / 3600 ))h ago"
            elif (( delta < 604800 )); then age="$(( delta / 86400 ))d ago"
            else age="$(( delta / 604800 ))w ago"
            fi
          fi
          page="${_dim}${age}${_reset}"
        fi

        echo -e "  ${pname}  ${pbranch}  ${pdirty}  ${psync}  ${page}"

      done <<< "$names"

      echo ""
      ;;

    cd)
      if [ -z "$2" ]; then
        echo -e "${_dim}usage:${_reset} proj cd ${_blue}<name>${_reset}"
        return 1
      fi
      local entry=$(__proj_get "$2")
      if [ -z "$entry" ]; then
        echo -e "${_red}✗${_reset} not found: ${_bold}$2${_reset}"
        return 1
      fi
      local path=$(__proj_field "$entry" 2)
      local host=$(__proj_field "$entry" 3)
      local hook=$(__proj_hook "$entry")
      if [ "$host" = "local" ]; then
        if [ ! -d "$path" ]; then
          if mkdir -p "$path" 2>/dev/null; then
            echo -e "${_yellow}!${_reset} created ${_blue}$path${_reset}"
          else
            echo -e "${_red}✗${_reset} could not create ${_blue}$path${_reset}"
            return 1
          fi
        fi
        echo -e "${_green}▸${_reset} ${_bold}$2${_reset} ${_dim}→${_reset} ${_blue}$path${_reset}"
        builtin cd "$path" && ls
        if [ -n "$hook" ]; then
          echo -e "${_dim}  hook:${_reset} ${_cyan}$hook${_reset}"
          eval "$hook"
        fi
      else
        echo -e "${_green}▸${_reset} ${_bold}$2${_reset} ${_dim}→${_reset} ${_yellow}$host${_reset}:${_blue}$path${_reset}"
        local remote_cmd="if [ ! -d '$path' ]; then mkdir -p '$path' && echo '  ! created $path'; fi && cd '$path' && ls"
        [ -n "$hook" ] && remote_cmd="if [ ! -d '$path' ]; then mkdir -p '$path' && echo '  ! created $path'; fi && cd '$path' && $hook && ls"
        ssh -F ~/.ssh/config "$host" -t "bash --init-file <(echo '${remote_cmd}')"
      fi
      ;;

    code)
      if [ -z "$2" ]; then
        echo -e "${_dim}usage:${_reset} proj code ${_blue}<name>${_reset}"
        return 1
      fi
      local entry=$(__proj_get "$2")
      if [ -z "$entry" ]; then
        echo -e "${_red}✗${_reset} not found: ${_bold}$2${_reset}"
        return 1
      fi
      local path=$(__proj_field "$entry" 2)
      local host=$(__proj_field "$entry" 3)
      if [ "$host" = "local" ]; then
        if [ ! -d "$path" ]; then
          if mkdir -p "$path" 2>/dev/null; then
            echo -e "${_yellow}!${_reset} created ${_blue}$path${_reset}"
          else
            echo -e "${_red}✗${_reset} could not create ${_blue}$path${_reset}"
            return 1
          fi
        fi
        echo -e "${_green}▸${_reset} opening ${_bold}$2${_reset} in VS Code"
        command code "$path"
      else
        echo -e "${_green}▸${_reset} opening ${_bold}$2${_reset} ${_dim}via${_reset} ${_yellow}$host${_reset} in VS Code"
        command code --folder-uri "vscode-remote://ssh-remote+$host$path"
      fi
      ;;

    cursor)
      if [ -z "$2" ]; then
        echo -e "${_dim}usage:${_reset} proj cursor ${_blue}<name>${_reset}"
        return 1
      fi
      local entry=$(__proj_get "$2")
      if [ -z "$entry" ]; then
        echo -e "${_red}✗${_reset} not found: ${_bold}$2${_reset}"
        return 1
      fi
      local path=$(__proj_field "$entry" 2)
      local host=$(__proj_field "$entry" 3)
      if [ "$host" = "local" ]; then
        if [ ! -d "$path" ]; then
          if mkdir -p "$path" 2>/dev/null; then
            echo -e "${_yellow}!${_reset} created ${_blue}$path${_reset}"
          else
            echo -e "${_red}✗${_reset} could not create ${_blue}$path${_reset}"
            return 1
          fi
        fi
        echo -e "${_green}▸${_reset} opening ${_bold}$2${_reset} in Cursor"
        command cursor "$path"
      else
        echo -e "${_green}▸${_reset} opening ${_bold}$2${_reset} ${_dim}via${_reset} ${_yellow}$host${_reset} in Cursor"
        command cursor --folder-uri "vscode-remote://ssh-remote+$host$path"
      fi
      ;;

    info)
      if [ -z "$2" ]; then
        echo -e "${_dim}usage:${_reset} proj info ${_blue}<name>${_reset}"
        return 1
      fi
      local entry=$(__proj_get "$2")
      if [ -z "$entry" ]; then
        echo -e "${_red}✗${_reset} not found: ${_bold}$2${_reset}"
        return 1
      fi
      local path=$(__proj_field "$entry" 2)
      local host=$(__proj_field "$entry" 3)
      local hook=$(__proj_hook "$entry")
      local tags=$(__proj_tags "$entry")
      echo ""
      echo -e "  ${_bold}$2${_reset}"
      echo -e "  ${_dim}path${_reset}  $path"
      echo -e "  ${_dim}host${_reset}  $host"
      if [ -n "$hook" ]; then
        echo -e "  ${_dim}hook${_reset}  ${_cyan}$hook${_reset}"
      fi
      if [ -n "$tags" ]; then
        echo -e "  ${_dim}tags${_reset}  ${_magenta}$tags${_reset}"
      fi
      if [ "$host" = "local" ]; then
        echo -e "  ${_dim}git${_reset}   $(__proj_git_status "$path")"
      fi
      echo ""
      ;;

    export)
      local outfile="${2:-}"
      if [ -n "$outfile" ]; then
        cp "$PROJ_FILE" "$outfile"
        echo -e "${_green}✓${_reset} exported to ${_blue}$outfile${_reset}"
      else
        cat "$PROJ_FILE"
      fi
      ;;

    import)
      local infile="$2"
      if [ -z "$infile" ]; then
        echo -e "${_dim}usage:${_reset} proj import ${_blue}<file|->${_reset}"
        return 1
      fi
      if [ "$infile" = "-" ]; then
        infile="/dev/stdin"
      elif [ ! -f "$infile" ]; then
        echo -e "${_red}✗${_reset} file not found: ${_bold}$infile${_reset}"
        return 1
      fi
      local count=0 skipped=0
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name
        name=$(echo "$line" | awk -F':::' '{print $1}')
        if [ -n "$(__proj_get "$name")" ]; then
          (( skipped++ ))
        else
          echo "$line" >> "$PROJ_FILE"
          (( count++ ))
        fi
      done < "$infile"
      echo -e "${_green}✓${_reset} imported ${_bold}$count${_reset} projects${skipped:+, ${_dim}skipped $skipped duplicates${_reset}}"
      ;;
    
    edit)
      local tmpfile
      tmpfile=$(mktemp)
      cp "$PROJ_FILE" "$tmpfile"
      ${EDITOR:-nano} "$tmpfile"
      mv "$tmpfile" "$PROJ_FILE"
      echo -e "${_green}✓${_reset} config updated"
      ;;

    ""|help)
      echo ""
      echo -e "  ${_bold}proj${_reset} ${_dim}— project manager${_reset}"
      echo ""
      printf "  ${_green}%-8s${_reset} %-27s %s\n" "add"    "<name> <path> [host]" "register project"
      printf "  ${_green}%-8s${_reset} %-27s %s\n" "del"    "<name>"               "remove project"
      printf "  ${_green}%-8s${_reset} %-27s %s\n" "rename" "<old> <new>"           "rename project"
      printf "  ${_green}%-8s${_reset} %-27s %s\n" "path"   "<name> <new-path>"    "change project path"
      printf "  ${_green}%-8s${_reset} %-27s %s\n" "cd"     "<name>"               "cd + run hook"
      printf "  ${_green}%-8s${_reset} %-27s %s\n" "code"   "<name>"               "open in VS Code"
      printf "  ${_green}%-8s${_reset} %-27s %s\n" "cursor" "<name>"               "open in Cursor"
      printf "  ${_green}%-8s${_reset} %-27s %s\n" "hook"   "<name> <cmd>"         "set cd hook"
      printf "  ${_green}%-8s${_reset} %-27s %s\n" "unhook" "<name>"               "remove cd hook"
      printf "  ${_green}%-8s${_reset} %-27s %s\n" "tag"    "<name> <tag>"          "add a tag"
      printf "  ${_green}%-8s${_reset} %-27s %s\n" "untag"  "<name> <tag>"          "remove a tag"
      printf "  ${_green}%-8s${_reset} %-27s %s\n" "info"   "<name>"               "project details + git"
      printf "  ${_green}%-8s${_reset} %-27s %s\n" "ls"     "[tag]"                "fuzzy pick (fzf)"
      printf "  ${_green}%-8s${_reset} %-27s %s\n" "status" "[tag]"                "git status dashboard"
      printf "  ${_green}%-8s${_reset} %-27s %s\n" "export" "[file]"               "export config"
      printf "  ${_green}%-8s${_reset} %-27s %s\n" "import" "<file>"               "import config"
      echo ""
      ;;

    *)
      echo -e "${_red}✗${_reset} unknown command: ${_bold}$1${_reset}"
      echo -e "${_dim}  run${_reset} proj help ${_dim}for usage${_reset}"
      return 1
      ;;
  esac
}

# ── autocomplete ─────────────────────────────────────────────────────

_proj_complete() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"

  local cmds="add del rename cd code cursor hook unhook tag untag info path ls status export import help edit"

  if (( COMP_CWORD == 1 )); then
    COMPREPLY=( $(compgen -W "$cmds" -- "$cur") )
    return
  fi

  local subcmd="${COMP_WORDS[1]}"

  case "$subcmd" in
    cd|code|del|cursor|hook|info|path|rename|tag)
      if (( COMP_CWORD == 2 )); then
        local projects=$(awk -F':::' '{print $1}' "$PROJ_FILE" 2>/dev/null)
        COMPREPLY=( $(compgen -W "$projects" -- "$cur") )
      fi
      ;;
    untag)
      if (( COMP_CWORD == 2 )); then
        local projects=$(awk -F':::' '{print $1}' "$PROJ_FILE" 2>/dev/null)
        COMPREPLY=( $(compgen -W "$projects" -- "$cur") )
      elif (( COMP_CWORD == 3 )); then
        local projname="${COMP_WORDS[2]}"
        local entry=$(__proj_get "$projname" 2>/dev/null)
        if [ -n "$entry" ]; then
          local tags=$(__proj_tags "$entry" | tr ',' ' ')
          COMPREPLY=( $(compgen -W "$tags" -- "$cur") )
        fi
      fi
      ;;
    ls|status)
      if (( COMP_CWORD == 2 )); then
        local tags=$(awk -F':::' '{n=split($5,t,","); for(i=1;i<=n;i++) if(t[i]!="") print t[i]}' "$PROJ_FILE" 2>/dev/null | sort -u)
        COMPREPLY=( $(compgen -W "$tags" -- "$cur") )
      fi
      ;;
    import|export)
      ;;
  esac
}
complete -F _proj_complete proj