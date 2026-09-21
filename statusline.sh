#!/usr/bin/env bash
# =============================================================================
#  cockpit-nav - Claude Code statusline (bash)
#
#  Base visual: "Cockpit" by RX
#      https://statusline.sh/community/cockpit-4shq
#  Campos trazidos de: "Minimalist (fork)(fork)(fork)" by hieu
#      https://statusline.sh/community/minimalist-fork-fork-fork-yv5B
#      -> diretorio, branch do git, tempo para reset dos rate limits
#
#  Requer jq OU python3 para ler o JSON que o Claude Code manda na stdin.
# =============================================================================
set -u
LC_ALL=C   # decimais invariantes: sem isso, um locale pt_BR quebra o custo

INPUT="$(cat)"
export INPUT_JSON="$INPUT"

# ----------------------------------------------------------------------------
# Configuracao (tudo ajustavel por variavel de ambiente)
# ----------------------------------------------------------------------------
BAR_W="${SL_BAR_WIDTH:-30}"   # largura do Cockpit
DIR_MODE="${SL_DIR_MODE:-basename}"   # basename | full
DIR_MAX="${SL_DIR_MAX:-28}"
SHOW_GIT=1;  [ "${SL_NO_GIT:-0}"  = "1" ] && SHOW_GIT=0
SHOW_COST=1; [ "${SL_NO_COST:-0}" = "1" ] && SHOW_COST=0

# Glifos.
# Escritos como escapes \u para ficarem legiveis: os icones da Nerd Font vivem
# na Private Use Area e apareceriam como caixinhas vazias num editor.
#
# O Cockpit usa U+FFED e U+FF65 (formas halfwidth de quadrado e ponto medio).
# Essas formas nao existem na maioria das fontes de terminal -- inclusive na
# JetBrainsMono Nerd Font -- e o fallback do terminal traz outra fonte, com
# metrica diferente, que desalinha a barra. U+25A0 e U+00B7 sao o MESMO
# desenho nas formas normais, presentes e com exatamente 1 celula de largura.
# A barra do Cockpit sao quadradinhos pequenos com vao entre eles, nao um
# bloco solido: U+25AA (small square) reproduz isso, U+25A0 preencheria a
# celula inteira e a barra sairia continua.
__SQ_SMALL=$'▪'                   # quadrado pequeno  -- o fiel ao Cockpit
__DOT=$'·'                        # ponto medio
G_FILL="${SL_FILL_GLYPH-$__SQ_SMALL}"
G_EMPTY="${SL_EMPTY_GLYPH-$__DOT}"
# Alternativas de cheio:  $'■' quadrado grande, $'▁' trilho fino,
#                         $'━' linha grossa, $'█' bloco
# Alternativas de vazio:  $'─' linha fina, $'┄' tracejado,
#                         $'░' sombra leve
G_CLEAN=$'✓'                      # check
G_DIRTY=$'✗'                      # x
G_ELLIPSIS=$'…'                   # truncamento

# Icones da Nerd Font. Use '-' e nao ':-' na expansao, para que definir a
# variavel como string vazia realmente desligue o icone.
__NF_BRANCH=$''                  # powerline branch
__NF_RESET=$''                   # relogio
G_BRANCH="${SL_BRANCH_ICON-$__NF_BRANCH}"
G_RESET="${SL_RESET_ICON-$__NF_RESET}"
# Alternativas de reset: $'' (refresh), $'' (refresh material).
# Sem Nerd Font, desligue os dois:  SL_BRANCH_ICON= SL_RESET_ICON=

# Paleta -- exatamente a do Cockpit, sem cor nova.
# Os campos adicionados reusam esses mesmos tons: o diretorio herda a cor
# padrao do terminal em negrito e o branch a mesma em esmaecido, que e o
# idioma que o Cockpit ja usa para par rotulo/valor.
C_MODEL='1;38;2;255;255;255;48;2;43;47;58'   # branco sobre ardosia
C_BLUE='1;38;2;143;184;218'                  # tokens
C_BLUE_D='2;38;2;143;184;218'
C_SAGE='38;2;156;192;159'                    # janela de 5h
C_SAGE_D='2;38;2;156;192;159'
C_AMBER='38;2;216;184;112'                   # janela de 7d
C_AMBER_D='2;38;2;216;184;112'
C_DIR='1'                                    # diretorio: fg padrao, negrito
C_BRANCH='2'                                 # branch: fg padrao, esmaecido

__sgr()   { printf '\033[%sm' "$1"; }
__reset() { printf '\033[0m'; }
__emit() {
  local style="$1" text="$2"
  [ -n "$style" ] && __sgr "$style"
  printf '%s' "$text"
  [ -n "$style" ] && __reset
  return 0
}

# ----------------------------------------------------------------------------
# Leitura do JSON de entrada
# ----------------------------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  __field() {
    printf '%s' "$INPUT_JSON" | jq -r --arg p "$1" '
      ($p | split(".")) as $parts
      | reduce $parts[] as $k (.; if type == "object" and has($k) then .[$k] else null end)
      | if . == null then "" else (if type == "string" then . else tostring end) end
    ' 2>/dev/null
  }
elif command -v node >/dev/null 2>&1; then
  # Node e o fallback mais confiavel: o proprio Claude Code roda nele.
  __field() {
    PATH_ARG="$1" node -e '
      let cur;
      try { cur = JSON.parse(process.env.INPUT_JSON || "{}"); } catch { cur = null; }
      for (const k of (process.env.PATH_ARG || "").split(".")) {
        if (cur && typeof cur === "object" && k in cur) cur = cur[k];
        else { cur = null; break; }
      }
      process.stdout.write(cur === null || cur === undefined ? "" : String(cur));
    ' 2>/dev/null
  }
else
  if command -v python3 >/dev/null 2>&1; then __PY=python3
  elif command -v python >/dev/null 2>&1; then __PY=python
  else __PY=""; fi
  __field() {
    [ -z "$__PY" ] && { printf ''; return; }
    PATH_ARG="$1" "$__PY" - <<'PYEOF' 2>/dev/null
import json, os
d = json.loads(os.environ.get('INPUT_JSON','{}') or '{}')
cur = d
for part in os.environ.get('PATH_ARG','').split('.'):
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        cur = None
        break
if cur is None:              print('', end='')
elif isinstance(cur, bool):  print('true' if cur else 'false', end='')
else:                        print(cur, end='')
PYEOF
  }
fi

__norm_int() {
  local v="${1%%.*}"
  case "$v" in ''|*[!0-9]*) printf '0' ;; *) printf '%s' "$v" ;; esac
}
__pct_int() {
  local p
  p="$(printf '%s' "${1:-0}" | awk '{ v=$0+0; if (v<0) v=0; if (v>100) v=100; printf "%d", int(v+0.5) }')"
  printf '%s' "${p:-0}"
}

# ----------------------------------------------------------------------------
# Formatadores
# ----------------------------------------------------------------------------
__bar() {
  local pct="$1" width="$2" filled="$3" empty="$4" p n e i out=""
  p="$(__pct_int "$pct")"
  n=$(( (p * width + 50) / 100 ))
  e=$((width - n))
  for ((i=0; i<n; i++)); do out+="$filled"; done
  for ((i=0; i<e; i++)); do out+="$empty"; done
  printf '%s' "$out"
}
__fmt_token() {
  local n w rem dec
  n="$(__norm_int "$1")"
  if [ "$n" -lt 1000 ]; then printf '%s' "$n"; return; fi
  if [ "$n" -lt 1000000 ]; then
    w=$((n / 1000)); rem=$((n - w * 1000)); dec=$((rem / 100))
    if [ "$dec" -eq 0 ]; then printf '%dk' "$w"; else printf '%d.%dk' "$w" "$dec"; fi
    return
  fi
  w=$((n / 1000000)); rem=$((n - w * 1000000)); dec=$((rem / 100000))
  if [ "$dec" -eq 0 ]; then printf '%dM' "$w"; else printf '%d.%dM' "$w" "$dec"; fi
}
__cost_fmt() { printf '%s' "${1:-0}" | awk '{ printf "$%.2f", $0+0 }'; }
__truncate() {
  local s="$1" n="$2"
  if [ "$n" -le 0 ] || [ "${#s}" -le "$n" ]; then printf '%s' "$s"; return; fi
  if [ "$n" -le 1 ]; then printf '%s' "${s:0:$n}"; return; fi
  printf '%s%s' "${s:0:$((n-1))}" "$G_ELLIPSIS"
}
# Junta icone e tempo com um espaco, e some com o espaco se o icone
# estiver desligado. Sem isso o glifo cola nos digitos.
__reset_label() {
  if [ -n "$G_RESET" ]; then printf '%s %s' "$G_RESET" "$1"
  else printf '%s' "$1"; fi
}

# ----------------------------------------------------------------------------
# Diretorio
# ----------------------------------------------------------------------------
__basename() { local s="${1%/}"; s="${s%\\}"; s="${s##*/}"; printf '%s' "${s##*\\}"; }
__tildify() {
  local s="$1" home="${HOME%/}"
  if [ -n "$home" ] && [[ "$s" == "$home"* ]]; then printf '~%s' "${s#$home}"; return; fi
  if [[ "$s" =~ ^/(Users|home)/[^/]+(.*)$ ]]; then printf '~%s' "${BASH_REMATCH[2]}"; return; fi
  printf '%s' "$s"
}
__compact() {
  printf '%s' "$1" | awk 'BEGIN{FS="/"} {
    out=""
    for (i=1; i<=NF; i++) {
      if (i==NF || $i == "" || $i == "~") piece = $i
      else piece = substr($i, 1, 1)
      out = (i==1) ? piece : out "/" piece
    }
    printf "%s", out
  }'
}
__cwd() {
  local c
  c="$(__field workspace.current_dir)"
  [ -z "$c" ] && c="$(__field cwd)"
  printf '%s' "$c"
}
__dir_label() {
  local c s
  c="$(__cwd)"
  [ -z "$c" ] && { printf ''; return; }
  if [ "$DIR_MODE" = "full" ]; then
    s="$(__tildify "$c")"
    [ "${#s}" -gt "$DIR_MAX" ] && s="$(__compact "$s")"
    __truncate "$s" "$DIR_MAX"
    return
  fi
  s="$(__basename "$c")"
  [ -z "$s" ] && { printf '~'; return; }
  __truncate "$s" "$DIR_MAX"
}

# ----------------------------------------------------------------------------
# Git
# ----------------------------------------------------------------------------
__git_branch() {
  local c b
  c="$(__cwd)"
  if [ -n "$c" ] && command -v git >/dev/null 2>&1; then
    b="$(git -C "$c" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    [ -n "$b" ] && { printf '%s' "$b"; return; }
  fi
  __basename "$(__field workspace.git_worktree)"
}
__git_dirty() {
  local c
  c="$(__cwd)"
  if [ -n "$c" ] && command -v git >/dev/null 2>&1; then
    [ -n "$(git -C "$c" status --porcelain 2>/dev/null)" ] && { printf '1'; return; }
  fi
  printf '0'
}

# ----------------------------------------------------------------------------
# Tempo ate o reset dos rate limits.
# Aceita epoch em segundos, epoch em milissegundos ou ISO-8601.
# ----------------------------------------------------------------------------
__tick() {
  if [ -n "${STATUSLINE_CLOCK_OVERRIDE:-}" ]; then printf '%s' "$STATUSLINE_CLOCK_OVERRIDE"
  else date +%s; fi
}
__to_epoch() {
  local v="$1" n
  [ -z "$v" ] && { printf '0'; return; }
  case "$v" in
    *[!0-9.]*) ;;   # nao e numero puro -> tenta ISO abaixo
    *)
      n="${v%%.*}"
      [ -z "$n" ] && { printf '0'; return; }
      # acima de 1e12 veio em milissegundos
      if [ "${#n}" -gt 12 ]; then printf '%s' "$((n / 1000))"; else printf '%s' "$n"; fi
      return ;;
  esac
  n="$(date -d "$v" +%s 2>/dev/null)" || n="$(date -j -f '%Y-%m-%dT%H:%M:%SZ' "$v" +%s 2>/dev/null)"
  printf '%s' "$(__norm_int "${n:-0}")"
}
__reset_in() {
  local t d h m dd hh
  t="$(__norm_int "$(__to_epoch "$1")")"
  [ "$t" -le 0 ] && { printf ''; return; }
  d=$((t - $(__tick)))
  [ "$d" -le 0 ] && { printf ''; return; }
  if [ "$d" -lt 60 ];    then printf '<1m'; return; fi
  if [ "$d" -lt 3600 ];  then printf '%dm' "$((d / 60))"; return; fi
  if [ "$d" -lt 86400 ]; then
    h=$((d / 3600)); m=$(((d % 3600) / 60))
    printf '%dh%02dm' "$h" "$m"; return
  fi
  dd=$((d / 86400)); hh=$(((d % 86400) / 3600))
  printf '%dd%dh' "$dd" "$hh"
}

# =============================================================================
#  LINHA 1 - identica a do Cockpit: chip do modelo, esforco, contexto, custo.
# =============================================================================
__emit "$C_MODEL" " $(__field 'model.display_name') "

if [ "$(__field 'thinking.enabled')" = 'true' ]; then
  __lvl="$(__field 'effort.level')"
  [ -n "$__lvl" ] && __emit '' " | $__lvl"
fi

__ctx_pct="$(__field 'context_window.used_percentage')"
__emit '' '  '
__emit "$C_BLUE_D" 'tok '
__emit "$C_BLUE" "$(__fmt_token "$(__field 'context_window.total_input_tokens')")/$(__fmt_token "$(__field 'context_window.context_window_size')") ($(__pct_int "$__ctx_pct")%)"
__emit "$C_BLUE" ' '
__emit '' "$(__bar "$__ctx_pct" "$BAR_W" "$G_FILL" "$G_EMPTY")"

[ "$SHOW_COST" = "1" ] && __emit '' "  $(__cost_fmt "$(__field 'cost.total_cost_usd')")"

# =============================================================================
#  LINHA 2 - a linha de uso do Cockpit, intacta, com o tempo de reset
#  acrescentado depois de cada barra na cor daquela janela.
# =============================================================================
__p5="$(__field 'rate_limits.five_hour.used_percentage')"
__p7="$(__field 'rate_limits.seven_day.used_percentage')"
if [ -n "$__p5" ] || [ -n "$__p7" ]; then
  __reset; printf '\n'

  __emit '' ' usage  '

  __emit "$C_SAGE_D" '5h '
  __emit "$C_SAGE"   "$(__bar "$__p5" "$BAR_W" "$G_FILL" "$G_EMPTY")"
  __emit "$C_SAGE"   ' '
  __r5="$(__reset_in "$(__field 'rate_limits.five_hour.resets_at')")"
  [ -n "$__r5" ] && __emit "$C_SAGE_D" "$(__reset_label "$__r5") "

  __emit "$C_AMBER_D" '7d '
  __emit "$C_AMBER"   "$(__bar "$__p7" "$BAR_W" "$G_FILL" "$G_EMPTY")"
  __emit "$C_AMBER"   ' '
  __r7="$(__reset_in "$(__field 'rate_limits.seven_day.resets_at')")"
  [ -n "$__r7" ] && __emit "$C_AMBER_D" "$(__reset_label "$__r7")"
fi

# =============================================================================
#  LINHA 3 - onde voce esta: diretorio e branch. Linha propria para nao
#  alargar as duas do Cockpit, que ficam na largura original.
# =============================================================================
__dir="$(__dir_label)"
__br=""
if [ "$SHOW_GIT" = "1" ]; then
  __br="$(__git_branch)"
  [ "$__br" = "HEAD" ] && __br=""
fi

if [ -n "$__dir" ] || [ -n "$__br" ]; then
  __reset; printf '\n'

  [ -n "$__dir" ] && __emit "$C_DIR" " $__dir"

  if [ -n "$__br" ]; then
    [ -z "$__dir" ] && __emit '' ' '
    if [ -n "$G_BRANCH" ]; then __emit "$C_BRANCH" "  $G_BRANCH $__br"
    else                        __emit "$C_BRANCH" "  $__br"; fi
    if [ "$(__git_dirty)" = '1' ]; then __emit "$C_DIR"    " $G_DIRTY"
    else                                __emit "$C_SAGE_D" " $G_CLEAN"; fi
  fi
fi

__reset
exit 0
