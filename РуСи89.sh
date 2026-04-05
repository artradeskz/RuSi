#!/bin/sh
# Лицензия ISC

# Авторские права (c) 2026 ---

# Разрешается использовать, копировать, изменять и/или распространять данное
# программное обеспечение для любых целей как с оплатой, так и без нее,
# при условии сохранения вышеуказанного уведомления об авторских правах

# ПРОГРАММНОЕ ОБЕСПЕЧЕНИЕ ПРЕДОСТАВЛЯЕТСЯ "КАК ЕСТЬ" И АВТОР ОТКАЗЫВАЕТСЯ ОТ ВСЕХ ГАРАНТИЙ,
# ВКЛЮЧАЯ ЛЮБЫЕ ПОДРАЗУМЕВАЕМЫЕ ГАРАНТИИ ТОВАРНОЙ ПРИГОДНОСТИ И
# ПРИГОДНОСТИ ДЛЯ КОНКРЕТНОЙ ЦЕЛИ. НИ ПРИ КАКИХ ОБСТОЯТЕЛЬСТВАХ АВТОР НЕ НЕСЕТ ОТВЕТСТВЕННОСТИ ЗА
# ЛЮБЫЕ СПЕЦИАЛЬНЫЕ, ПРЯМЫЕ, КОСВЕННЫЕ ИЛИ СЛУЧАЙНЫЕ УБЫТКИ ИЛИ ЛЮБЫЕ ДРУГИЕ УБЫТКИ,
# ВОЗНИКШИЕ В РЕЗУЛЬТАТЕ ПОТЕРИ ИСПОЛЬЗОВАНИЯ, ДАННЫХ ИЛИ ПРИБЫЛИ, БУДЬ ТО
# В РЕЗУЛЬТАТЕ ДЕЙСТВИЙ ДОГОВОРА, ХАЛАТНОСТИ ИЛИ ИНЫХ ДЕЙСТВИЙ, ВОЗНИКАЮЩИХ ИЗ
# ИЛИ В СВЯЗИ С ИСПОЛЬЗОВАНИЕМ ИЛИ РАБОТОЙ ДАННОГО ПРОГРАММНОГО ОБЕСПЕЧЕНИЯ.

# ============================================================================
# РуСи89cc_ru.sh — автономный парсер + компилятор РуСи_89 (C89) (x86-64 ELF64)
# ============================================================================
#
# Использование:
# sh РуСи89cc_ru.sh < prog.c > a.out
# sh РуСи89cc_ru.sh --no-libc < prog.c > a.out   (пропустить встроенную libc)

# --- core/header.sh ---
set -euf
#LC_ALL=C
IFS=''
_EOL='
'
_TAB="	"
# Очистка PATH: внешние команды не требуются
PATH=
# Совместимость оболочек: алиасы в bash, POSIX-подобные в zsh
shopt -s expand_aliases >/dev/null 2>&1 || :
setopt sh_word_split null_glob glob_subst \
	no_glob no_multios no_equals 2>/dev/null || :
# Запасной вариант для ksh/mksh: 'local' может отсутствовать, используйте 'typeset'
command -v local >/dev/null 2>&1 || alias local=typeset >/dev/null 2>&1 || :

# Запасной вариант: если 'test' не является встроенной командой, оберните через command -p
if ! command -v test >/dev/null 2>&1; then test () { command -p test "$@"; }; fi

# --- Вспомогательные функции вывода ---
# Определение лучшего доступного примитива вывода:
# printf > print > echo > command -p printf
# _printn1: вывод строки без перевода строки  _printr1: вывод строки с переводом строки
if command -v printf >/dev/null 2>&1
then
	_printn1 () { printf '%s' "$1"; }
	_printr1 () { printf '%s\n' "$@"; }
elif command -v print >/dev/null 2>&1
then
	_printn1 () { echo -n -E "$1"; }
	_printr1 () { echo -E "$@"; }
elif command -v echo >/dev/null 2>&1
then
	_printn1 () { echo -n "$1"; }
	_printr1 () { echo "$@"; }
else
	# запасной вариант для yash
	_printn1 () { command -p printf '%s' "$1"; }
	_printr1 () { command -p printf '%s\n' "$@"; }
fi

# --- Вспомогательные функции для возврата нескольких значений и динамических локальных переменных ---
# Упаковка присваиваний переменных в REPLY (режим добавления).
# Вызывающий распаковывает с помощью: eval "$REPLY"  (устанавливает глобальные)
# или: eval "local$REPLY"  (устанавливает локальные)
# Значения, содержащие ', должны быть предварительно экранированы с помощью _esc_sq.
# Использование: REPLY=; _retv имя значение; _retva префикс индекс значение; eval "local$REPLY"
_retv () { REPLY="$REPLY $1='$2'"; }
_retva () { REPLY="$REPLY ${1}_${2}='$3'"; }

# --- система модулей (заглушка, все модули встроены) ---
_MOD="$_EOL"
_mod_has () { return 0; }
_mod_add () { :; }
use () { :; }

# --- modules/str/repeat.sh ---
# Повторение строки N раз методом возведения в квадрат.
_repeat () {
	case "${2:-}" in
		0|"") return;; 1) REPLY="$1"; return;; 2) REPLY="$1$1"; return;;
		3) REPLY="$1$1$1"; return;; 4) REPLY="$1$1$1$1"; return;;
	esac
	local VALUE="$1" COUNT="$2" POW=2; REPLY=
	while :; do
		if test $POW -gt $COUNT; then
			test $COUNT -gt 0 || break
			REPLY="$REPLY$VALUE" VALUE="$1"
			COUNT=$((COUNT - (POW / 2))) POW=2
			continue; fi
		VALUE="$VALUE$VALUE" POW=$((POW * 2))
	done
}

# Генератор паттерна '???...?' с мемоизацией (используется для разбиения длинных строк ввода).
_questn () {
	eval "case \${_questn$1:-} in \"\")
		_repeat \\? $1; _questn$1=\$REPLY
	;; esac; REPLY=\$_questn$1"
}

# --- modules/str/core.sh ---
# Преобразование строки в верхний регистр (a-z → A-Z). Результат в REPLY. ДОБАВИТЬ КИРИЛЛИЦУ
_ucase () {
	local _s="$1" _r= _c _byte1 _byte2 _char _UCASE_HB=""
	
	while test ${#_s} -gt 0; do
		_c="${_s%"${_s#?}"}"; _s="${_s#?}"
		
		# Получаем числовой код байта
		_byte1=$(printf '%d' "'$_c" 2>/dev/null)
		
		# Если это старший байт UTF-8 (D0 или D1)
		if test "$_byte1" -eq 208 || test "$_byte1" -eq 209; then
			_UCASE_HB=$_byte1
			continue
		fi
		
		# Если есть сохраненный старший байт - собираем русскую букву
		if test -n "$_UCASE_HB"; then
			_byte2=$_byte1
			if test "$_UCASE_HB" -eq 208; then
				# D0 xx -> А-Я, а-п
				_char=$(printf "\\$(($_UCASE_HB/64))$((($_UCASE_HB/8)%8))$(($_UCASE_HB%8))\\$(($_byte2/64))$((($_byte2/8)%8))$(($_byte2%8))")
			else
				# D1 xx -> Ё, ё, р-я
				_char=$(printf "\\$(($_UCASE_HB/64))$((($_UCASE_HB/8)%8))$(($_UCASE_HB%8))\\$(($_byte2/64))$((($_byte2/8)%8))$(($_byte2%8))")
			fi
			_UCASE_HB=""
		else
			_char=$_c
		fi
		
		# Преобразование в верхний регистр
		case "$_char" in
		# Латиница
		a) _r="${_r}A";; b) _r="${_r}B";; c) _r="${_r}C";;
		d) _r="${_r}D";; e) _r="${_r}E";; f) _r="${_r}F";;
		g) _r="${_r}G";; h) _r="${_r}H";; i) _r="${_r}I";;
		j) _r="${_r}J";; k) _r="${_r}K";; l) _r="${_r}L";;
		m) _r="${_r}M";; n) _r="${_r}N";; o) _r="${_r}O";;
		p) _r="${_r}P";; q) _r="${_r}Q";; r) _r="${_r}R";;
		s) _r="${_r}S";; t) _r="${_r}T";; u) _r="${_r}U";;
		v) _r="${_r}V";; w) _r="${_r}W";; x) _r="${_r}X";;
		y) _r="${_r}Y";; z) _r="${_r}Z";;
		# Кириллица (строчные)
		а) _r="${_r}А";; б) _r="${_r}Б";; в) _r="${_r}В";;
		г) _r="${_r}Г";; д) _r="${_r}Д";; е) _r="${_r}Е";;
		ё) _r="${_r}Ё";; ж) _r="${_r}Ж";; з) _r="${_r}З";;
		и) _r="${_r}И";; й) _r="${_r}Й";; к) _r="${_r}К";;
		л) _r="${_r}Л";; м) _r="${_r}М";; н) _r="${_r}Н";;
		о) _r="${_r}О";; п) _r="${_r}П";; р) _r="${_r}Р";;
		с) _r="${_r}С";; т) _r="${_r}Т";; у) _r="${_r}У";;
		ф) _r="${_r}Ф";; х) _r="${_r}Х";; ц) _r="${_r}Ц";;
		ч) _r="${_r}Ч";; ш) _r="${_r}Ш";; щ) _r="${_r}Щ";;
		ъ) _r="${_r}Ъ";; ы) _r="${_r}Ы";; ь) _r="${_r}Ь";;
		э) _r="${_r}Э";; ю) _r="${_r}Ю";; я) _r="${_r}Я";;
		# Заглавные и остальное без изменений
		*) _r="${_r}${_char}";;
		esac
	done
	REPLY="$_r"
}


# Преобразование символа верхнего регистра в нижний. Результат в REPLY.
_lcase () {
	case "$1" in
	# Латиница
	A) REPLY=a;; B) REPLY=b;; C) REPLY=c;; D) REPLY=d;;
	E) REPLY=e;; F) REPLY=f;; G) REPLY=g;; H) REPLY=h;;
	I) REPLY=i;; J) REPLY=j;; K) REPLY=k;; L) REPLY=l;;
	M) REPLY=m;; N) REPLY=n;; O) REPLY=o;; P) REPLY=p;;
	Q) REPLY=q;; R) REPLY=r;; S) REPLY=s;; T) REPLY=t;;
	U) REPLY=u;; V) REPLY=v;; W) REPLY=w;; X) REPLY=x;;
	Y) REPLY=y;; Z) REPLY=z;;
	# Кириллица (заглавные → строчные)
	А) REPLY=а;; Б) REPLY=б;; В) REPLY=в;; Г) REPLY=г;;
	Д) REPLY=д;; Е) REPLY=е;; Ё) REPLY=ё;; Ж) REPLY=ж;;
	З) REPLY=з;; И) REPLY=и;; Й) REPLY=й;; К) REPLY=к;;
	Л) REPLY=л;; М) REPLY=м;; Н) REPLY=н;; О) REPLY=о;;
	П) REPLY=п;; Р) REPLY=р;; С) REPLY=с;; Т) REPLY=т;;
	У) REPLY=у;; Ф) REPLY=ф;; Х) REPLY=х;; Ц) REPLY=ц;;
	Ч) REPLY=ч;; Ш) REPLY=ш;; Щ) REPLY=щ;; Ъ) REPLY=ъ;;
	Ы) REPLY=ы;; Ь) REPLY=ь;; Э) REPLY=э;; Ю) REPLY=ю;;
	Я) REPLY=я;;
	*) REPLY=;;
	esac
}

# Преобразование строки верхнего регистра в нижний. Результат в REPLY.
_lcase_str () {
	local _s="$1" _c _r=
	while test ${#_s} -gt 0; do
		_c="${_s%"${_s#?}"}"; _s="${_s#?}"
		_lcase "$_c"
		case "$REPLY" in '') _r="$_r$_c";; *) _r="$_r$REPLY";; esac
	done
	REPLY="$_r"
}




# Извлечь следующий UTF-8 символ из CODE, результат в _CHAR, продвинуть CODE
# Использует глобальную переменную CODE, изменяет её
# Результат в _CHAR (глобальная переменная)
_get_utf8_char() {
	local _c _byte1 _UCASE_HB=""
	_CHAR=""
	_c="${CODE%"${CODE#?}"}"
	_byte1=$(printf '%d' "'$_c" 2>/dev/null)
	
	# Если это старший байт UTF-8 (D0 или D1)
	if test "$_byte1" -eq 208 || test "$_byte1" -eq 209; then
		_UCASE_HB=$_byte1
		_CHAR="$_c"
		CODE="${CODE#?}"
		_c="${CODE%"${CODE#?}"}"
		_CHAR="${_CHAR}$_c"
		CODE="${CODE#?}"
	else
		_CHAR="$_c"
		CODE="${CODE#?}"
	fi
}

# Накопление UTF-8 идентификатора (поддерживает латиницу, цифры, подчёркивание, кириллицу)
_accum_utf8() {
    local _res="" _b1 _b2 _c1 _c2
    while test ${#CODE} -gt 0; do
        _c1="${CODE%"${CODE#?}"}"
        _b1=$(printf '%d' "'$_c1" 2>/dev/null)

        # ASCII: 0-9
        if test "$_b1" -ge 48 && test "$_b1" -le 57; then
            _res="${_res}${_c1}"; CODE="${CODE#?}"
        # ASCII: A-Z
        elif test "$_b1" -ge 65 && test "$_b1" -le 90; then
            _res="${_res}${_c1}"; CODE="${CODE#?}"
        # ASCII: a-z
        elif test "$_b1" -ge 97 && test "$_b1" -le 122; then
            _res="${_res}${_c1}"; CODE="${CODE#?}"
        # Символ _
        elif test "$_b1" -eq 95; then
            _res="${_res}${_c1}"; CODE="${CODE#?}"
        # Кириллица UTF-8 (старший байт 208 или 209)
        elif test "$_b1" -eq 208 || test "$_b1" -eq 209; then
            CODE="${CODE#?}"
            if test ${#CODE} -eq 0; then
                CODE="${_c1}${CODE}"; break
            fi
            _c2="${CODE%"${CODE#?}"}"
            _b2=$(printf '%d' "'$_c2" 2>/dev/null)

            # Второй байт UTF-8 всегда 128..191
            if test "$_b2" -ge 128 && test "$_b2" -le 191; then
                _res="${_res}${_c1}${_c2}"
                CODE="${CODE#?}"
            else
                CODE="${_c1}${CODE}"; break
            fi
        else
            break
        fi
    done
    MATCH="$_res"
}


# --- modules/io/readall.sh ---
# Чтение всего stdin в REPLY (заменяет /bin/cat для eval "$(_readall)").
_readall () {
	REPLY=
	while IFS='' read -r _l; do REPLY="$REPLY$_l$_EOL"; done
	REPLY="$REPLY$_l"
}

# --- modules/pos/core.sh ---
# Подсчет переводов строк в потребленной/пропущенной строке, обновление _LN/_COL.
# Быстрый путь без перевода строки: просто добавляет длину строки к _COL.
_nlcount () {
	local _s="$1" _h
	case "$_s" in *"$_EOL"*)
		while :; do
			_h="${_s#*"$_EOL"}"
			case "$_h" in *"$_EOL"*)
				_LN=$((_LN+1)); _s="$_h";;
			*)
				_LN=$((_LN+1))
				_COL=$((${#_h} + 1))
				return;;
			esac
		done;;
	*)
		_COL=$((_COL + ${#_s}));;
	esac
}

# Проверка CONSUMED как числа RFC 8259: [-](0|[1-9]d*)[.d+][eE[+-]d+]
_numck () {
	local _n="$CONSUMED"
	case "$_n" in '-'*) _n="${_n#-}";; esac
	case "$_n" in
		'') _error NUMBER;;
		'0'[0-9]*) _error NUMBER;;
		'0'*) _n="${_n#0}";;
		[1-9]*) _n="${_n#[1-9]}"; _n="${_n#"${_n%%[!0-9]*}"}";;
		*) _error NUMBER;;
	esac
	case "$_n" in '.'*)
		_n="${_n#.}"
		case "$_n" in [0-9]*) ;; *) _error NUMBER;; esac
		_n="${_n#"${_n%%[!0-9]*}"}";;
	esac
	case "$_n" in [eE]*)
		_n="${_n#?}"
		case "$_n" in '+'*|'-'*) _n="${_n#?}";; esac
		case "$_n" in [0-9]*) ;; *) _error NUMBER;; esac
		_n="${_n#"${_n%%[!0-9]*}"}";;
	esac
	case "$_n" in '') ;; *) _error NUMBER;; esac
}

# --- modules/err/core.sh ---

_error () {
	IFS=' '
	eval "_a=\"\${_SRC$_LN:-}\""
	_printr1 "$* at $_LN:$_COL"
	case "$_a" in ?*)
		_printr1 "  $_a"
		_repeat ' ' $_COL; _printr1 "  ${REPLY}^"
	;; esac
	exit 1
}

# --- modules/ast/core.sh ---

# --- Подача ввода ---
# Чтение из stdin в буфер CODE по одной строке за раз.
# Строки длиной > 128 символов разбиваются на части перед добавлением.
# ast_read:   чтение одной строки, разбиение на части в CODE
# ast_feed: дозаполнение когда CODE < 16 символов (плотный цикл, большинство веток)
# ast_more: дозаполнение когда CODE < 1024 символов (массовое чтение для имен/ключевых слов)
alias ast_read='if IFS= read -r _line
	then
		_RD=$((_RD + 1)); eval "_SRC$_RD=\"\$_line\""
		while test ${#_line} -gt 128; do
			_questn 128
			_b="${_line#${REPLY}}"; _a="${_line%"$_b"}"
			CODE="$CODE$_a"; _line="$_b"
		done
		CODE="$CODE$_line$_EOL"
	else _EOF=1; CODE="$CODE$_line"
		case "$_line" in ?*) _RD=$((_RD + 1)); eval "_SRC$_RD=\"\$_line\"";; esac
	fi'

alias ast_feed='if test ${#CODE} -lt 16 -a $_EOF -eq 0; then ast_read; fi'
alias ast_more='
	while test ${#CODE} -lt 1024 -a $_EOF -eq 0
	do ast_read; done'

# --- Операции на уровне символов ---
# ast_consume  - перемещение 1-4 символов из CODE в CONSUMED
# ast_skip     - отбрасывание 1-3 символов или пробелов из CODE
# _ast_xfer    - базовая: добавление обрезанного префикса в CONSUMED
# _ast_xbulk   - базовая: добавление REST в CONSUMED, продвижение CODE
alias _ast_xfer='CONSUMED="$CONSUMED${CODE%"$REST"}"; CODE="$REST"'
alias _ast_xbulk='CONSUMED="$CONSUMED$REST"; CODE="${CODE#"$REST"}"'
alias ast_consume='REST="${CODE#?}"; _ast_xfer; _COL=$((_COL+1))'
alias ast_consume2='REST="${CODE#??}"; _ast_xfer; _COL=$((_COL+2))'
alias ast_consume3='REST="${CODE#???}"; _ast_xfer; _COL=$((_COL+3))'
alias ast_consume4='REST="${CODE#????}"; _ast_xfer; _COL=$((_COL+4))'

alias ast_skip='CODE="${CODE#?}"; _COL=$((_COL+1))'
alias ast_skip2='CODE="${CODE#??}"; _COL=$((_COL+2))'
alias ast_skip3='CODE="${CODE#???}"; _COL=$((_COL+3))'
alias _ast_advcol='_COL=$((_COL+${#REST}))'
alias ast_skip_ws='REST="${CODE%%[! $_TAB]*}"; _ast_advcol; CODE="${CODE#"$REST"}"'
alias ast_skip_wse='REST="${CODE%%[! $_TAB$_EOL]*}"
	CODE="${CODE#"$REST"}"; _nlcount "$REST"'
# Варианты с учетом перевода строки
alias ast_skip_nl='CODE="${CODE#?}"; _LN=$((_LN+1)); _COL=1'
alias ast_skip2_nl='CODE="${CODE#??}"; _LN=$((_LN+1)); _COL=1'
alias ast_consume_nl='REST="${CODE#?}"; _ast_xfer; _LN=$((_LN+1)); _COL=1'
# ast_bulk - добавление REST в CONSUMED, продвижение CODE, цикл
alias ast_bulk='_ast_xbulk; _ast_advcol; continue'
alias ast_bulk_nl='_ast_xbulk; _nlcount "$REST"; continue'

# --- Операции со стеком AST ---
# ast_new       - сохранение состояния, сохранение CONSUMED как V<n>, сброс CONSUMED
# ast_push      - создание узла дерева X<n>=<состояние>, добавление индекса в стек NODES
# ast_pop       - извлечение стека состояния + узлов
# Примитивы (используются составными алиасами ниже):
# ast_attach    - присоединение узла к родителю
# ast_collapse  - свертывание обертки с одним дочерним элементом без значения в дочерний
# pars_attach_op        - ast_attach + приоритет оператора: если предыдущий сиблинг Ab/Ob/Pb/Bu,
# перестраивает так, чтобы оператор забрал предыдущего сиблинга
# Составные операции закрытия (все начинаются с ast_pop):
# ast_discard      - ast_pop + отбрасывание (для временных состояний, например Cs)
# ast_close        - ast_pop + ast_attach
# pars_close_op    - ast_pop + pars_attach_op
# ast_close_col    - ast_pop + ast_collapse + ast_attach
# pars_close_op_col  - ast_pop + ast_collapse + pars_attach_op
# pars_close_redir - ast_close + ошибка, если цель перенаправления пуста
# ast_flush     - сброс CONSUMED как дочернего элемента Tx (a"b"c)
alias ast_new='STATES="$STATES $STATE"; V=$((V + 1))
	case "$CONSUMED" in "");; *) local V$V="$CONSUMED";;esac
	CONSUMED='
alias ast_push='local X$V="$STATE"
	PARN="${NODES##*" "}"
	eval "PARNT=\"\${X$PARN%% *}\""
	NODE=$V; NODES="$NODES $NODE"'
alias ast_pop='STATE="${STATES##*" "}"; STATES="${STATES%" ${STATE}"}"
	PARN="${NODES##*" "}"
	case "$CONSUMED" in ?*) local V$PARN="$CONSUMED";; esac
	CONSUMED=
	NODE=$PARN; NODES="${NODES%" $NODE"}"; PARN="${NODES##*" "}"
	eval "PARNT=\"\${X$PARN%% *}\""'

alias ast_attach='eval "X$PARN=\"\$X$PARN \$NODE\""'
alias ast_collapse='eval "_D=\"\$X$NODE\""; _C="${_D#* }"
	case "$_C" in "$_D"|*" "*) ;;
	*) eval "case \"\${V$NODE:-}\" in \"\") unset X$NODE; NODE=$_C;; esac";;
	esac'
alias ast_discard='ast_pop;unset X$NODE'
alias ast_close='ast_pop;ast_attach'
alias ast_close_col='ast_pop;ast_collapse;ast_attach'
alias ast_flush='case "$CONSUMED" in ?*) ast_Tx;ast_close;; esac'

# Регистрация типов узлов AST. Каждый тип получает алиас ast_XX,
# который создает новый узел, устанавливает STATE и помещает в стек.
# Регистрация типов узлов AST. Выводит определения алиасов для eval.
# Использование: eval "$(ast_tokens "Ty Pe Na Me")"
ast_tokens () {
	IFS=' '
	for _s in $1; do
		_printr1 "alias ast_$_s=\"ast_new;STATE=$_s;ast_push\""
	done
	IFS=''
}

# Обход AST от корня, вывод V<n> (значение) и X<n> (узел) в порядке дерева.
# Формат: X<n>='<тип> [<индексы_дочерних>...]'  V<n>='<значение>'
# Использует динамическую область видимости для доступа к локальным V<n>/X<n> вызывающего.
ast_out () {
	set -- 0
	while test $# -gt 0; do
		NODE=$1; shift
		eval "_pq=\"\${V$NODE:-}\"; _D=\"\$X$NODE\""
		case "$_pq" in ?*)
			# Экранирование одинарных кавычек в значениях: 'abc'd'ef' -> 'abc'\''ef'
			case "$_pq" in *"'"*)
				_printn1 "V$NODE="
				while :; do
					case "$_pq" in *"'"*) ;; *) break;; esac
					_printn1 "'${_pq%%"'"*}'\\'"; _pq="${_pq#*"'"}"
				done
				_printn1 "'$_pq'$_EOL";;
			*) _printr1 "V$NODE='$_pq'";;
			esac;; esac
		_printr1 "X$NODE='$_D'"
		_C="${_D#* }"
		case "$_C" in "$_D") ;; ?*)
			IFS=' '; set -- $_C "$@"; IFS=''
		;; esac
	done
}

# --- Проверка прогресса (обнаружение циклов) ---
# Двухуровневая проверка:
# 1. Точное повторение (та же длина CODE + состояние + позиция) → немедленная ошибка
# 2. Входные данные не потреблены за 4096 итераций → застревание в циклическом состоянии
alias pars_progress='case "${#CODE}.$STATE.$_LN.$_COL" in "$_PREV") _error INTERNAL LOOP;; esac; _PREV="${#CODE}.$STATE.$_LN.$_COL"; case ${#CODE} in "$_PLEN") _PLC=$((_PLC+1)); case $((_PLC>4096)) in 1) _error INTERNAL LOOP;; esac;; *) _PLEN=${#CODE}; _PLC=0;; esac'

# --- Вспомогательные функции сообщения об ошибках ---
alias _pars_err='eval "_a=\"\${_EXP_$STATE:-token}\""; _error "expected: $_a"'
alias _pars_err_eof='eval "_a=\"\${_EXP_$STATE:-token}\""; _error "unexpected end of input, expected: $_a"'

# --- Эпилог парсера (обертки эмиттера, футер, диспетчеризация) ---
# $1=имя грамматики, $2=аргумент скрипта (необязательное переопределение команды).
# Вызывается после определения функции эмиттера.
_ast_core_pars_epilogue () {
	eval "_emit_${1}_root () { _emit_$1 \"\$@\"; }"
	. "$_DIR/core/footer.sh"
	eval "unast_$1 () { _readall; eval \"\$REPLY\"; _emit_${1}_root 0; _printr1 \"\$REPLY\"; }"
	eval "reast_$1 () { pars_$1 | unast_$1; }"
	case "${PARS_LIB:-}" in "")
		case "${2:-}" in
		"") "pars_$1";;
		pars_*|unast_*|reast_*) $2;;
		*) _printr1 "usage: $0 [pars_$1 | unast_$1 | reast_$1]"
			_printr1 "  pars_$1    parse stdin, print AST (default)"
			_printr1 "  unast_$1   read AST from stdin, print source"
			_printr1 "  reast_$1   parse stdin, print source (round-trip)"
			exit 1;;
		esac
	;; esac
}

# --- modules/ast/consume.sh ---
# --- Потребление совпадений/операторов ---
# Используется парсерами с сопоставлением ключевых слов или подъемом по приоритету.
# Пропуск MATCH из CODE (пропуск ключевого слова после нечувствительного к регистру совпадения)
alias ast_skip_match='CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH}))'
# Потребление MATCH в CONSUMED (ключевое слово потребляется как значение AST)
alias ast_consume_match='CONSUMED="$MATCH"; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH}))'
# Потребление _OP в CONSUMED (потребление бинарного оператора)
alias ast_consume_op='CONSUMED="$_OP"; CODE="${CODE#"$_OP"}"; _COL=$((_COL+${#_OP}))'

# --- modules/ast/prec.sh ---
# --- Вспомогательные функции подъема по приоритету ---
# Используется парсерами с директивами #!precedence.
# Закрытие узла и повторный вход в цикл подъема по приоритету.
alias ast_close_xc='ast_close; _XC=1; _PREV=; continue'
alias ast_close_col_xc='ast_close_col; _XC=1; _PREV=; continue'

# --- modules/ast/comment.sh ---
# --- Пропуск комментариев ---
# Используется парсерами с директивами #!comment.
# Требует переменные, установленные сгенерированным парсером:
# _CMT_S, _CMT_SL  -- маркер начала блочного комментария и его длина
# _CMT_E, _CMT_EL  -- маркер конца блочного комментария и его длина

# Строчный комментарий: пропуск от текущей позиции до конца строки
alias ast_cmt_line='REST="${CODE%%"$_EOL"*}"
	CODE="${CODE#"$REST"}"
	_COL=$((_COL+${#REST})); continue'

# Блочный комментарий: пропуск от маркера начала до маркера конца с подсчетом переводов строк
alias ast_cmt_block='CODE="${CODE#"$_CMT_S"}"; _COL=$((_COL+_CMT_SL))
	while :; do
		case "$CODE" in *"$_CMT_E"*)
			REST="${CODE%%"$_CMT_E"*}"
			_nlcount "$REST"
			CODE="${CODE#"$REST"}"; CODE="${CODE#"$_CMT_E"}"
			_COL=$((_COL+_CMT_EL)); break;;
		*) case $_EOF in 1) _error "unclosed comment";; esac
			_nlcount "$CODE"; CODE=; ast_read;;
		esac
	done; continue'

# --- modules/c89/parser.sh ---

alias ast_Ca="ast_new;STATE=Ca;ast_push"
alias ast_Cb="ast_new;STATE=Cb;ast_push"
alias ast_Cc="ast_new;STATE=Cc;ast_push"
alias ast_Cd="ast_new;STATE=Cd;ast_push"
alias ast_Ce="ast_new;STATE=Ce;ast_push"
alias ast_Cf="ast_new;STATE=Cf;ast_push"
alias ast_Cg="ast_new;STATE=Cg;ast_push"
alias ast_Ch="ast_new;STATE=Ch;ast_push"
alias ast_Ci="ast_new;STATE=Ci;ast_push"
alias ast_Cj="ast_new;STATE=Cj;ast_push"
alias ast_Ck="ast_new;STATE=Ck;ast_push"
alias ast_Cl="ast_new;STATE=Cl;ast_push"
alias ast_Cm="ast_new;STATE=Cm;ast_push"
alias ast_Cn="ast_new;STATE=Cn;ast_push"
alias ast_Co="ast_new;STATE=Co;ast_push"
alias ast_Cp="ast_new;STATE=Cp;ast_push"
alias ast_Cq="ast_new;STATE=Cq;ast_push"
alias ast_Cr="ast_new;STATE=Cr;ast_push"
alias ast_Cs="ast_new;STATE=Cs;ast_push"
alias ast_Ct="ast_new;STATE=Ct;ast_push"
alias ast_Cu="ast_new;STATE=Cu;ast_push"
alias ast_Cv="ast_new;STATE=Cv;ast_push"
alias ast_Cw="ast_new;STATE=Cw;ast_push"
alias ast_Cx="ast_new;STATE=Cx;ast_push"
alias ast_Cy="ast_new;STATE=Cy;ast_push"
alias ast_Cz="ast_new;STATE=Cz;ast_push"
alias ast_C1="ast_new;STATE=C1;ast_push"
alias ast_C2="ast_new;STATE=C2;ast_push"
alias ast_C3="ast_new;STATE=C3;ast_push"
alias ast_C4="ast_new;STATE=C4;ast_push"
alias ast_C5="ast_new;STATE=C5;ast_push"
alias ast_C6="ast_new;STATE=C6;ast_push"
alias ast_C7="ast_new;STATE=C7;ast_push"
alias ast_C8="ast_new;STATE=C8;ast_push"
alias ast_C9="ast_new;STATE=C9;ast_push"
alias ast_C10="ast_new;STATE=C10;ast_push"
alias ast_C11="ast_new;STATE=C11;ast_push"
alias ast_C12="ast_new;STATE=C12;ast_push"
alias ast_C13="ast_new;STATE=C13;ast_push"
alias ast_C14="ast_new;STATE=C14;ast_push"
alias ast_C15="ast_new;STATE=C15;ast_push"
alias ast_C16="ast_new;STATE=C16;ast_push"
alias ast_C17="ast_new;STATE=C17;ast_push"
alias ast_C18="ast_new;STATE=C18;ast_push"
alias ast_C19="ast_new;STATE=C19;ast_push"
alias ast_C20="ast_new;STATE=C20;ast_push"
alias ast_C21="ast_new;STATE=C21;ast_push"
alias ast_C22="ast_new;STATE=C22;ast_push"
alias ast_C23="ast_new;STATE=C23;ast_push"
alias ast_C24="ast_new;STATE=C24;ast_push"
alias ast_C25="ast_new;STATE=C25;ast_push"
alias ast_C26="ast_new;STATE=C26;ast_push"
alias ast_C27="ast_new;STATE=C27;ast_push"
alias ast_C28="ast_new;STATE=C28;ast_push"
alias ast_C29="ast_new;STATE=C29;ast_push"
alias ast_C30="ast_new;STATE=C30;ast_push"
alias ast_C31="ast_new;STATE=C31;ast_push"
alias ast_C32="ast_new;STATE=C32;ast_push"
alias ast_C33="ast_new;STATE=C33;ast_push"
alias ast_C34="ast_new;STATE=C34;ast_push"
alias ast_C35="ast_new;STATE=C35;ast_push"
alias ast_C36="ast_new;STATE=C36;ast_push"
alias ast_C37="ast_new;STATE=C37;ast_push"
alias ast_C38="ast_new;STATE=C38;ast_push"
alias ast_C39="ast_new;STATE=C39;ast_push"
alias ast_C40="ast_new;STATE=C40;ast_push"
alias ast_C41="ast_new;STATE=C41;ast_push"
alias ast_C42="ast_new;STATE=C42;ast_push"
alias ast_C43="ast_new;STATE=C43;ast_push"
alias ast_C44="ast_new;STATE=C44;ast_push"
alias ast_C45="ast_new;STATE=C45;ast_push"
alias ast_C46="ast_new;STATE=C46;ast_push"
alias ast_C47="ast_new;STATE=C47;ast_push"
alias ast_C48="ast_new;STATE=C48;ast_push"
alias ast_C49="ast_new;STATE=C49;ast_push"
alias ast_C50="ast_new;STATE=C50;ast_push"
alias ast_C51="ast_new;STATE=C51;ast_push"
alias ast_C52="ast_new;STATE=C52;ast_push"
alias ast_C53="ast_new;STATE=C53;ast_push"
alias ast_C54="ast_new;STATE=C54;ast_push"
alias ast_C55="ast_new;STATE=C55;ast_push"
alias ast_C56="ast_new;STATE=C56;ast_push"
alias ast_C57="ast_new;STATE=C57;ast_push"
alias ast_C58="ast_new;STATE=C58;ast_push"
alias ast_C59="ast_new;STATE=C59;ast_push"
alias ast_C60="ast_new;STATE=C60;ast_push"
alias ast_C61="ast_new;STATE=C61;ast_push"
alias ast_C62="ast_new;STATE=C62;ast_push"
alias ast_C63="ast_new;STATE=C63;ast_push"
alias ast_C64="ast_new;STATE=C64;ast_push"
alias ast_C65="ast_new;STATE=C65;ast_push"
alias ast_C66="ast_new;STATE=C66;ast_push"
alias ast_C67="ast_new;STATE=C67;ast_push"
alias ast_C68="ast_new;STATE=C68;ast_push"
alias ast_C69="ast_new;STATE=C69;ast_push"
alias ast_C70="ast_new;STATE=C70;ast_push"
alias ast_C71="ast_new;STATE=C71;ast_push"
alias ast_C72="ast_new;STATE=C72;ast_push"
alias ast_C73="ast_new;STATE=C73;ast_push"
alias ast_C74="ast_new;STATE=C74;ast_push"
alias ast_C75="ast_new;STATE=C75;ast_push"
alias ast_C76="ast_new;STATE=C76;ast_push"
alias ast_C77="ast_new;STATE=C77;ast_push"
alias ast_C78="ast_new;STATE=C78;ast_push"
alias ast_C79="ast_new;STATE=C79;ast_push"
alias ast_C80="ast_new;STATE=C80;ast_push"
alias ast_C81="ast_new;STATE=C81;ast_push"
alias ast_C82="ast_new;STATE=C82;ast_push"
alias ast_C83="ast_new;STATE=C83;ast_push"
alias ast_C84="ast_new;STATE=C84;ast_push"
alias ast_C85="ast_new;STATE=C85;ast_push"
alias ast_C86="ast_new;STATE=C86;ast_push"
alias ast_C87="ast_new;STATE=C87;ast_push"
alias ast_C88="ast_new;STATE=C88;ast_push"
alias ast_C89="ast_new;STATE=C89;ast_push"
alias ast_C90="ast_new;STATE=C90;ast_push"
alias ast_C91="ast_new;STATE=C91;ast_push"
alias ast_C92="ast_new;STATE=C92;ast_push"
alias ast_C93="ast_new;STATE=C93;ast_push"
alias ast_C94="ast_new;STATE=C94;ast_push"
alias ast_C95="ast_new;STATE=C95;ast_push"
alias ast_C96="ast_new;STATE=C96;ast_push"
alias ast_C97="ast_new;STATE=C97;ast_push"
alias ast_C98="ast_new;STATE=C98;ast_push"
alias ast_C99="ast_new;STATE=C99;ast_push"
alias ast_C100="ast_new;STATE=C100;ast_push"
alias ast_C101="ast_new;STATE=C101;ast_push"
alias ast_C102="ast_new;STATE=C102;ast_push"
alias ast_C103="ast_new;STATE=C103;ast_push"
alias ast_C104="ast_new;STATE=C104;ast_push"
alias ast_C105="ast_new;STATE=C105;ast_push"
alias ast_C106="ast_new;STATE=C106;ast_push"
alias ast_C107="ast_new;STATE=C107;ast_push"
alias ast_C108="ast_new;STATE=C108;ast_push"
alias ast_C109="ast_new;STATE=C109;ast_push"
alias ast_C110="ast_new;STATE=C110;ast_push"
alias ast_C111="ast_new;STATE=C111;ast_push"
alias ast_C112="ast_new;STATE=C112;ast_push"
alias ast_C113="ast_new;STATE=C113;ast_push"
alias ast_C114="ast_new;STATE=C114;ast_push"
alias ast_C115="ast_new;STATE=C115;ast_push"
alias ast_C116="ast_new;STATE=C116;ast_push"
alias ast_C117="ast_new;STATE=C117;ast_push"
alias ast_C118="ast_new;STATE=C118;ast_push"
alias ast_C119="ast_new;STATE=C119;ast_push"
alias ast_C120="ast_new;STATE=C120;ast_push"
alias ast_C121="ast_new;STATE=C121;ast_push"
alias ast_C122="ast_new;STATE=C122;ast_push"
alias ast_C123="ast_new;STATE=C123;ast_push"
alias ast_C124="ast_new;STATE=C124;ast_push"
alias ast_C125="ast_new;STATE=C125;ast_push"
alias ast_C126="ast_new;STATE=C126;ast_push"
alias ast_C127="ast_new;STATE=C127;ast_push"
alias ast_C128="ast_new;STATE=C128;ast_push"
alias ast_C129="ast_new;STATE=C129;ast_push"
alias ast_C130="ast_new;STATE=C130;ast_push"
alias ast_C131="ast_new;STATE=C131;ast_push"
alias ast_C132="ast_new;STATE=C132;ast_push"
alias ast_C133="ast_new;STATE=C133;ast_push"
alias ast_C134="ast_new;STATE=C134;ast_push"
alias ast_C135="ast_new;STATE=C135;ast_push"
alias ast_C136="ast_new;STATE=C136;ast_push"
alias ast_C137="ast_new;STATE=C137;ast_push"
alias ast_C138="ast_new;STATE=C138;ast_push"
alias ast_C139="ast_new;STATE=C139;ast_push"
alias ast_C140="ast_new;STATE=C140;ast_push"
alias ast_C141="ast_new;STATE=C141;ast_push"
alias ast_C142="ast_new;STATE=C142;ast_push"
alias ast_C143="ast_new;STATE=C143;ast_push"
alias ast_C144="ast_new;STATE=C144;ast_push"
alias ast_C145="ast_new;STATE=C145;ast_push"
alias ast_C146="ast_new;STATE=C146;ast_push"
alias ast_C147="ast_new;STATE=C147;ast_push"
alias ast_C148="ast_new;STATE=C148;ast_push"
alias ast_C149="ast_new;STATE=C149;ast_push"
alias ast_C150="ast_new;STATE=C150;ast_push"
alias ast_C151="ast_new;STATE=C151;ast_push"
alias ast_C152="ast_new;STATE=C152;ast_push"
alias ast_C153="ast_new;STATE=C153;ast_push"
alias ast_C154="ast_new;STATE=C154;ast_push"
alias ast_C155="ast_new;STATE=C155;ast_push"
alias ast_C156="ast_new;STATE=C156;ast_push"
alias ast_C157="ast_new;STATE=C157;ast_push"
alias ast_C158="ast_new;STATE=C158;ast_push"
alias ast_C159="ast_new;STATE=C159;ast_push"
alias ast_C160="ast_new;STATE=C160;ast_push"
alias ast_C161="ast_new;STATE=C161;ast_push"
alias ast_C162="ast_new;STATE=C162;ast_push"
alias ast_C163="ast_new;STATE=C163;ast_push"
alias ast_C164="ast_new;STATE=C164;ast_push"
alias ast_C165="ast_new;STATE=C165;ast_push"
alias ast_C166="ast_new;STATE=C166;ast_push"
alias ast_C167="ast_new;STATE=C167;ast_push"
alias ast_C168="ast_new;STATE=C168;ast_push"
alias ast_C169="ast_new;STATE=C169;ast_push"
alias ast_C170="ast_new;STATE=C170;ast_push"
alias ast_C171="ast_new;STATE=C171;ast_push"
alias ast_C172="ast_new;STATE=C172;ast_push"
alias ast_C173="ast_new;STATE=C173;ast_push"
alias ast_C174="ast_new;STATE=C174;ast_push"
alias ast_C175="ast_new;STATE=C175;ast_push"
alias ast_C176="ast_new;STATE=C176;ast_push"
alias ast_C177="ast_new;STATE=C177;ast_push"
alias ast_C178="ast_new;STATE=C178;ast_push"
alias ast_C179="ast_new;STATE=C179;ast_push"
alias ast_C180="ast_new;STATE=C180;ast_push"
alias ast_C181="ast_new;STATE=C181;ast_push"
alias ast_C182="ast_new;STATE=C182;ast_push"
alias ast_C183="ast_new;STATE=C183;ast_push"
alias ast_C184="ast_new;STATE=C184;ast_push"
alias ast_C185="ast_new;STATE=C185;ast_push"
alias ast_C186="ast_new;STATE=C186;ast_push"
alias ast_C187="ast_new;STATE=C187;ast_push"
alias ast_C188="ast_new;STATE=C188;ast_push"

# Коды состояний:
# Ca=_doc_  Cb=file_body  Cc=item  Cd=int_item  Ce=char_item  Cf=void_item  Cg=long_item  Ch=short_item  Ci=float_item  Cj=double_item  Ck=signed_item  Cl=unsigned_item  Cm=const_item  Cn=static_item  Co=extern_item  Cp=volatile_item  Cq=auto_item  Cr=register_item  Cs=typedef_item  Ct=struct_item  Cu=union_item  Cv=enum_item  Cw=decl_rest  Cx=ptr_decl  Cy=ident_decl  Cz=after_name  C1=func_def  C2=func_end  C3=func_block  C4=array_decl  C5=init_part  C6=more_decls  C7=declarator  C8=param  C9=param_rest  C10=param_ptr  C11=param_type  C12=param_struct  C13=param_union  C14=param_enum  C15=struct_rest  C16=enum_rest  C17=enum_tail  C18=enum_vars  C19=enumerator_list  C20=enumerator  C21=initializer  C22=brace_init  C23=return_item  C24=break_item  C25=continue_item  C26=goto_item  C27=if_item  C28=while_item  C29=for_item  C30=do_item  C31=switch_item  C32=case_item  C33=default_item  C34=sizeof_item  C35=pp_line  C36=block_item  C37=block_body  C38=expr_item  C39=expr  C40=atom  C41=sizeof_expr  C42=sizeof_body  C43=paren_expr  C44=arg_list  C45=str  C46=chr  C47=number  C48=ident  C49=_unary_1  C50=_unary_2  C51=_unary_3  C52=_unary_4  C53=_unary_5  C54=_unary_6
# продолжение: C55 C56 C57 C58 C59 C60 C61 C62 C63 C64 C65 C66 C67 C68 C69 C70 C71 C72 C73 C74 C75 C76 C77 C78 C79 C80 C81 C82 C83 C84 C85 C86 C87 C88 C89 C90 C91 C92 C93 C94 C95 C96 C97 C98 C99 C100 C101 C102 C103 C104 C105 C106 C107 C108 C109 C110 C111 C112 C113 C114 C115 C116 C117 C118 C119 C120 C121 C122 C123 C124 C125 C126 C127 C128 C129 C130 C131 C132 C133 C134 C135 C136 C137 C138 C139 C140 C141 C142 C143 C144 C145 C146 C147 C148 C149 C150 C151 C152 C153 C154 C155 C156 C157 C158 C159 C160 C161 C162 C163 C164 C165 C166 C167 C168 C169 C170 C171 C172 C173 C174 C175 C176 C177 C178 C179 C180 C181 C182 C183 C184 C185 C186 C187 C188
_c89_sg_C45='[\\"]*'
_c89_sg_C46='[\\'"'"']*'

_EXP_Ca='"\"" or '\'''\'''\'' or '\''I'\'' or '\''C'\'' or '\''V'\'' or '\''L'\'' or '\''S'\'' or '\''F'\'' or '\''D'\'' or '\''U'\'' or '\''E'\'' or '\''A'\'' or '\''R'\'' or '\''T'\'' or '\''B'\'' or '\''G'\'' or '\''#'\'' or '\''{'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''i'\'' or '\''c'\'' or '\''v'\'' or '\''l'\'' or '\''s'\'' or '\''f'\'' or '\''d'\'' or '\''u'\'' or '\''e'\'' or '\''a'\'' or '\''r'\'' or '\''t'\'' or '\''b'\'' or '\''g'\'' or identifier or [0-9a-fA-FxXuUlL.] or text'
_EXP_Cb='"\"" or '\'''\'''\'' or '\''I'\'' or '\''C'\'' or '\''V'\'' or '\''L'\'' or '\''S'\'' or '\''F'\'' or '\''D'\'' or '\''U'\'' or '\''E'\'' or '\''A'\'' or '\''R'\'' or '\''T'\'' or '\''B'\'' or '\''G'\'' or '\''#'\'' or '\''{'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''i'\'' or '\''c'\'' or '\''v'\'' or '\''l'\'' or '\''s'\'' or '\''f'\'' or '\''d'\'' or '\''u'\'' or '\''e'\'' or '\''a'\'' or '\''r'\'' or '\''t'\'' or '\''b'\'' or '\''g'\'' or identifier or [0-9a-fA-FxXuUlL.] or text'
_EXP_Cc='"\"" or '\'''\'''\'' or '\''I'\'' or '\''C'\'' or '\''V'\'' or '\''L'\'' or '\''S'\'' or '\''F'\'' or '\''D'\'' or '\''U'\'' or '\''E'\'' or '\''A'\'' or '\''R'\'' or '\''T'\'' or '\''B'\'' or '\''G'\'' or '\''#'\'' or '\''{'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''i'\'' or '\''c'\'' or '\''v'\'' or '\''l'\'' or '\''s'\'' or '\''f'\'' or '\''d'\'' or '\''u'\'' or '\''e'\'' or '\''a'\'' or '\''r'\'' or '\''t'\'' or '\''b'\'' or '\''g'\'' or '\''w'\'' or identifier or [0-9a-fA-FxXuUlL.] or text'
_EXP_Cd=''\''*'\'' or '\'';'\'' or identifier'
_EXP_Ce=''\''*'\'' or '\'';'\'' or identifier'
_EXP_Cf=''\''*'\'' or '\'';'\'' or identifier'
_EXP_Cg=''\''*'\'' or '\'';'\'' or identifier'
_EXP_Ch=''\''*'\'' or '\'';'\'' or identifier'
_EXP_Ci=''\''*'\'' or '\'';'\'' or identifier'
_EXP_Cj=''\''*'\'' or '\'';'\'' or identifier'
_EXP_Ck=''\''*'\'' or '\'';'\'' or identifier'
_EXP_Cl=''\''*'\'' or '\'';'\'' or identifier'
_EXP_Cm=''\''*'\'' or '\'';'\'' or identifier'
_EXP_Cn=''\''*'\'' or '\'';'\'' or identifier'
_EXP_Co=''\''*'\'' or '\'';'\'' or identifier'
_EXP_Cp=''\''*'\'' or '\'';'\'' or identifier'
_EXP_Cq=''\''*'\'' or '\'';'\'' or identifier'
_EXP_Cr=''\''*'\'' or '\'';'\'' or identifier'
_EXP_Cs=''\''*'\'' or '\'';'\'' or identifier'
_EXP_Ct='identifier'
_EXP_Cu='identifier'
_EXP_Cv=''\''{'\'' or identifier'
_EXP_Cw=''\''*'\'' or '\'';'\'' or identifier'
_EXP_Cx=''\''*'\'' or '\'';'\'' or identifier'
_EXP_Cy='identifier'
_EXP_Cz=''\''('\'' or '\'';'\'' or '\''['\'' or '\''='\'' or '\'','\'''
_EXP_C1=''\''I'\'' or '\''C'\'' or '\''V'\'' or '\''L'\'' or '\''S'\'' or '\''F'\'' or '\''D'\'' or '\''U'\'' or '\''E'\'' or '\''i'\'' or '\''c'\'' or '\''v'\'' or '\''l'\'' or '\''s'\'' or '\''f'\'' or '\''d'\'' or '\''u'\'' or '\''e'\'' or '\'')'\'''
_EXP_C2=''\''{'\'' or '\'';'\'' or '\'','\'''
_EXP_C3='"\"" or '\'''\'''\'' or '\''I'\'' or '\''C'\'' or '\''V'\'' or '\''L'\'' or '\''S'\'' or '\''F'\'' or '\''D'\'' or '\''U'\'' or '\''E'\'' or '\''A'\'' or '\''R'\'' or '\''T'\'' or '\''B'\'' or '\''G'\'' or '\''#'\'' or '\''{'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''i'\'' or '\''c'\'' or '\''v'\'' or '\''l'\'' or '\''s'\'' or '\''f'\'' or '\''d'\'' or '\''u'\'' or '\''e'\'' or '\''a'\'' or '\''r'\'' or '\''t'\'' or '\''b'\'' or '\''g'\'' or '\''}'\'' or identifier or [0-9a-fA-FxXuUlL.] or text'
_EXP_C4='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or '\'']'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C5='"\"" or '\'''\'''\'' or '\''S'\'' or '\''{'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C6=''\'';'\'' or '\'','\'''
_EXP_C7=''\''*'\'' or identifier'
_EXP_C8=''\''I'\'' or '\''C'\'' or '\''V'\'' or '\''L'\'' or '\''S'\'' or '\''F'\'' or '\''D'\'' or '\''U'\'' or '\''E'\'' or '\''i'\'' or '\''c'\'' or '\''v'\'' or '\''l'\'' or '\''s'\'' or '\''f'\'' or '\''d'\'' or '\''u'\'' or '\''e'\'''
_EXP_C9=''\''*'\'' or identifier'
_EXP_C10=''\''*'\'' or identifier'
_EXP_C11=''\''I'\'' or '\''C'\'' or '\''V'\'' or '\''L'\'' or '\''S'\'' or '\''F'\'' or '\''D'\'' or '\''U'\'' or '\''E'\'' or '\''i'\'' or '\''c'\'' or '\''v'\'' or '\''l'\'' or '\''s'\'' or '\''f'\'' or '\''d'\'' or '\''u'\'' or '\''e'\'''
_EXP_C12='identifier'
_EXP_C13='identifier'
_EXP_C14='identifier'
_EXP_C15='identifier'
_EXP_C16='identifier'
_EXP_C17=''\''*'\'' or '\'';'\'' or identifier'
_EXP_C18=''\''*'\'' or '\'';'\'' or identifier'
_EXP_C19='identifier'
_EXP_C20='identifier'
_EXP_C21='"\"" or '\'''\'''\'' or '\''S'\'' or '\''{'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C22='"\"" or '\'''\'''\'' or '\''S'\'' or '\''{'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C23='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or '\'';'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C24=''\'';'\'''
_EXP_C25=''\'';'\'''
_EXP_C26='identifier'
_EXP_C27=''\''('\'''
_EXP_C28=''\''('\'''
_EXP_C29=''\''('\'''
_EXP_C30='"\"" or '\'''\'''\'' or '\''I'\'' or '\''C'\'' or '\''V'\'' or '\''L'\'' or '\''S'\'' or '\''F'\'' or '\''D'\'' or '\''U'\'' or '\''E'\'' or '\''A'\'' or '\''R'\'' or '\''T'\'' or '\''B'\'' or '\''G'\'' or '\''#'\'' or '\''{'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''i'\'' or '\''c'\'' or '\''v'\'' or '\''l'\'' or '\''s'\'' or '\''f'\'' or '\''d'\'' or '\''u'\'' or '\''e'\'' or '\''a'\'' or '\''r'\'' or '\''t'\'' or '\''b'\'' or '\''g'\'' or identifier or [0-9a-fA-FxXuUlL.] or text'
_EXP_C31=''\''('\'''
_EXP_C32='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C33=''\'':'\'''
_EXP_C34=''\''('\'''
_EXP_C35='identifier'
_EXP_C36='"\"" or '\'''\'''\'' or '\''I'\'' or '\''C'\'' or '\''V'\'' or '\''L'\'' or '\''S'\'' or '\''F'\'' or '\''D'\'' or '\''U'\'' or '\''E'\'' or '\''A'\'' or '\''R'\'' or '\''T'\'' or '\''B'\'' or '\''G'\'' or '\''#'\'' or '\''{'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''i'\'' or '\''c'\'' or '\''v'\'' or '\''l'\'' or '\''s'\'' or '\''f'\'' or '\''d'\'' or '\''u'\'' or '\''e'\'' or '\''a'\'' or '\''r'\'' or '\''t'\'' or '\''b'\'' or '\''g'\'' or '\''}'\'' or identifier or [0-9a-fA-FxXuUlL.] or text'
_EXP_C37='"\"" or '\'''\'''\'' or '\''I'\'' or '\''C'\'' or '\''V'\'' or '\''L'\'' or '\''S'\'' or '\''F'\'' or '\''D'\'' or '\''U'\'' or '\''E'\'' or '\''A'\'' or '\''R'\'' or '\''T'\'' or '\''B'\'' or '\''G'\'' or '\''#'\'' or '\''{'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''i'\'' or '\''c'\'' or '\''v'\'' or '\''l'\'' or '\''s'\'' or '\''f'\'' or '\''d'\'' or '\''u'\'' or '\''e'\'' or '\''a'\'' or '\''r'\'' or '\''t'\'' or '\''b'\'' or '\''g'\'' or '\''}'\'' or identifier or [0-9a-fA-FxXuUlL.] or text'
_EXP_C38='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C39='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C40='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C41=''\''('\'''
_EXP_C42='identifier'
_EXP_C43='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C44='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C45='"\"" or '\''\'\'''
_EXP_C46=''\''\'\'' or '\'''\'''\'''
_EXP_C49='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C50='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C51='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C52='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C53='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C54='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C55='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C56='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\'')'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C57=''\'')'\'''
_EXP_C58='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\'']'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C59=''\'']'\'''
_EXP_C60='identifier'
_EXP_C61='identifier'
_EXP_C64='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C65=''\'':'\'''
_EXP_C66='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C67='"\"" or '\'''\'''\'' or '\''I'\'' or '\''C'\'' or '\''V'\'' or '\''L'\'' or '\''S'\'' or '\''F'\'' or '\''D'\'' or '\''U'\'' or '\''E'\'' or '\''A'\'' or '\''R'\'' or '\''T'\'' or '\''B'\'' or '\''G'\'' or '\''#'\'' or '\''{'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''i'\'' or '\''c'\'' or '\''v'\'' or '\''l'\'' or '\''s'\'' or '\''f'\'' or '\''d'\'' or '\''u'\'' or '\''e'\'' or '\''a'\'' or '\''r'\'' or '\''t'\'' or '\''b'\'' or '\''g'\'' or identifier or [0-9a-fA-FxXuUlL.] or text'
_EXP_C90=''\''('\'' or '\'';'\'' or '\''['\'' or '\''='\'' or '\'','\'''
_EXP_C93=''\''{'\'' or '\'';'\'' or '\'','\'''
_EXP_C94=''\'','\'''
_EXP_C95=''\''I'\'' or '\''C'\'' or '\''V'\'' or '\''L'\'' or '\''S'\'' or '\''F'\'' or '\''D'\'' or '\''U'\'' or '\''E'\'' or '\''i'\'' or '\''c'\'' or '\''v'\'' or '\''l'\'' or '\''s'\'' or '\''f'\'' or '\''d'\'' or '\''u'\'' or '\''e'\'''
_EXP_C99=''\'';'\'' or '\'','\'''
_EXP_C101=''\'';'\'' or '\'','\'''
_EXP_C103=''\''*'\'' or identifier'
_EXP_C104=''\''['\'' or '\''='\'''
_EXP_C105='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or '\'']'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C106='"\"" or '\'''\'''\'' or '\''S'\'' or '\''{'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C107=''\''*'\'' or identifier'
_EXP_C115=''\''*'\'' or '\'';'\'' or identifier'
_EXP_C118=''\''{'\'' or '\''*'\'' or '\'';'\'' or identifier'
_EXP_C120=''\''}'\'''
_EXP_C121=''\''*'\'' or '\'';'\'' or identifier'
_EXP_C124=''\''}'\'''
_EXP_C125=''\''*'\'' or '\'';'\'' or identifier'
_EXP_C127=''\'','\'''
_EXP_C128='identifier'
_EXP_C129=''\''='\'''
_EXP_C130='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C132=''\'','\'' or '\''}'\'''
_EXP_C133='"\"" or '\'''\'''\'' or '\''S'\'' or '\''{'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C134=''\'';'\'''
_EXP_C135='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C136=''\'')'\'''
_EXP_C137='"\"" or '\'''\'''\'' or '\''I'\'' or '\''C'\'' or '\''V'\'' or '\''L'\'' or '\''S'\'' or '\''F'\'' or '\''D'\'' or '\''U'\'' or '\''E'\'' or '\''A'\'' or '\''R'\'' or '\''T'\'' or '\''B'\'' or '\''G'\'' or '\''#'\'' or '\''{'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''i'\'' or '\''c'\'' or '\''v'\'' or '\''l'\'' or '\''s'\'' or '\''f'\'' or '\''d'\'' or '\''u'\'' or '\''e'\'' or '\''a'\'' or '\''r'\'' or '\''t'\'' or '\''b'\'' or '\''g'\'' or identifier or [0-9a-fA-FxXuUlL.] or text'
_EXP_C138=''\''E'\'' or '\''e'\'''
_EXP_C139='"\"" or '\'''\'''\'' or '\''I'\'' or '\''C'\'' or '\''V'\'' or '\''L'\'' or '\''S'\'' or '\''F'\'' or '\''D'\'' or '\''U'\'' or '\''E'\'' or '\''A'\'' or '\''R'\'' or '\''T'\'' or '\''B'\'' or '\''G'\'' or '\''#'\'' or '\''{'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''i'\'' or '\''c'\'' or '\''v'\'' or '\''l'\'' or '\''s'\'' or '\''f'\'' or '\''d'\'' or '\''u'\'' or '\''e'\'' or '\''a'\'' or '\''r'\'' or '\''t'\'' or '\''b'\'' or '\''g'\'' or identifier or [0-9a-fA-FxXuUlL.] or text'
_EXP_C140='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C141=''\'')'\'''
_EXP_C142='"\"" or '\'''\'''\'' or '\''I'\'' or '\''C'\'' or '\''V'\'' or '\''L'\'' or '\''S'\'' or '\''F'\'' or '\''D'\'' or '\''U'\'' or '\''E'\'' or '\''A'\'' or '\''R'\'' or '\''T'\'' or '\''B'\'' or '\''G'\'' or '\''#'\'' or '\''{'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''i'\'' or '\''c'\'' or '\''v'\'' or '\''l'\'' or '\''s'\'' or '\''f'\'' or '\''d'\'' or '\''u'\'' or '\''e'\'' or '\''a'\'' or '\''r'\'' or '\''t'\'' or '\''b'\'' or '\''g'\'' or identifier or [0-9a-fA-FxXuUlL.] or text'
_EXP_C144='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or '\'';'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C145='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or '\'';'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C146='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or '\'')'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C147='"\"" or '\'''\'''\'' or '\''I'\'' or '\''C'\'' or '\''V'\'' or '\''L'\'' or '\''S'\'' or '\''F'\'' or '\''D'\'' or '\''U'\'' or '\''E'\'' or '\''A'\'' or '\''R'\'' or '\''T'\'' or '\''B'\'' or '\''G'\'' or '\''#'\'' or '\''{'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''i'\'' or '\''c'\'' or '\''v'\'' or '\''l'\'' or '\''s'\'' or '\''f'\'' or '\''d'\'' or '\''u'\'' or '\''e'\'' or '\''a'\'' or '\''r'\'' or '\''t'\'' or '\''b'\'' or '\''g'\'' or identifier or [0-9a-fA-FxXuUlL.] or text'
_EXP_C149=''\''w'\'' or '\''W'\'''
_EXP_C150=''\''('\'''
_EXP_C151='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C152=''\'')'\'''
_EXP_C153=''\'';'\'''
_EXP_C154='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C155=''\'')'\'''
_EXP_C156='"\"" or '\'''\'''\'' or '\''I'\'' or '\''C'\'' or '\''V'\'' or '\''L'\'' or '\''S'\'' or '\''F'\'' or '\''D'\'' or '\''U'\'' or '\''E'\'' or '\''A'\'' or '\''R'\'' or '\''T'\'' or '\''B'\'' or '\''G'\'' or '\''#'\'' or '\''{'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''i'\'' or '\''c'\'' or '\''v'\'' or '\''l'\'' or '\''s'\'' or '\''f'\'' or '\''d'\'' or '\''u'\'' or '\''e'\'' or '\''a'\'' or '\''r'\'' or '\''t'\'' or '\''b'\'' or '\''g'\'' or identifier or [0-9a-fA-FxXuUlL.] or text'
_EXP_C158=''\'':'\'''
_EXP_C159='"\"" or '\'''\'''\'' or '\''I'\'' or '\''C'\'' or '\''V'\'' or '\''L'\'' or '\''S'\'' or '\''F'\'' or '\''D'\'' or '\''U'\'' or '\''E'\'' or '\''A'\'' or '\''R'\'' or '\''T'\'' or '\''B'\'' or '\''G'\'' or '\''#'\'' or '\''{'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''i'\'' or '\''c'\'' or '\''v'\'' or '\''l'\'' or '\''s'\'' or '\''f'\'' or '\''d'\'' or '\''u'\'' or '\''e'\'' or '\''a'\'' or '\''r'\'' or '\''t'\'' or '\''b'\'' or '\''g'\'' or identifier or [0-9a-fA-FxXuUlL.] or text'
_EXP_C161='"\"" or '\'''\'''\'' or '\''I'\'' or '\''C'\'' or '\''V'\'' or '\''L'\'' or '\''S'\'' or '\''F'\'' or '\''D'\'' or '\''U'\'' or '\''E'\'' or '\''A'\'' or '\''R'\'' or '\''T'\'' or '\''B'\'' or '\''G'\'' or '\''#'\'' or '\''{'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''i'\'' or '\''c'\'' or '\''v'\'' or '\''l'\'' or '\''s'\'' or '\''f'\'' or '\''d'\'' or '\''u'\'' or '\''e'\'' or '\''a'\'' or '\''r'\'' or '\''t'\'' or '\''b'\'' or '\''g'\'' or identifier or [0-9a-fA-FxXuUlL.] or text'
_EXP_C163='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'
_EXP_C164=''\'')'\'''
_EXP_C165=''\'';'\'''
_EXP_C169='"\"" or '\'''\'''\'' or '\''I'\'' or '\''C'\'' or '\''V'\'' or '\''L'\'' or '\''S'\'' or '\''F'\'' or '\''D'\'' or '\''U'\'' or '\''E'\'' or '\''A'\'' or '\''R'\'' or '\''T'\'' or '\''B'\'' or '\''G'\'' or '\''#'\'' or '\''{'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''i'\'' or '\''c'\'' or '\''v'\'' or '\''l'\'' or '\''s'\'' or '\''f'\'' or '\''d'\'' or '\''u'\'' or '\''e'\'' or '\''a'\'' or '\''r'\'' or '\''t'\'' or '\''b'\'' or '\''g'\'' or '\''}'\'' or identifier or [0-9a-fA-FxXuUlL.] or text'
_EXP_C171=''\'';'\'''
_EXP_C173='identifier'
_EXP_C174=''\'')'\'''
_EXP_C175=''\''*'\'' or identifier'
_EXP_C176=''\'')'\'''
_EXP_C177=''\'','\'''
_EXP_C178='"\"" or '\'''\'''\'' or '\''S'\'' or '\''+'\'' or '\''&'\'' or '\''*'\'' or '\''~'\'' or '\''!'\'' or '\''-'\'' or '\''('\'' or '\''s'\'' or identifier or [0-9a-fA-FxXuUlL.]'

# Забрать последнего сиблинга у родителя, сделать его первым дочерним элементом текущего NODE
alias _steal='eval "_W=\"\${X$PARN##*\" \"}\"
	X$PARN=\"\${X$PARN% *}\"
	X$NODE=\"\$X$NODE \$_W\""'

_c89_parser_prec () {
	case "$1" in
		'=') REPLY=1;;
		'+=') REPLY=1;;
		'-=') REPLY=1;;
		'*=') REPLY=1;;
		'/=') REPLY=1;;
		'%=') REPLY=1;;
		'&=') REPLY=1;;
		'|=') REPLY=1;;
		'^=') REPLY=1;;
		'<<=') REPLY=1;;
		'>>=') REPLY=1;;
		'||') REPLY=2;;
		'&&') REPLY=3;;
		'|') REPLY=4;;
		'^') REPLY=5;;
		'&') REPLY=6;;
		'==') REPLY=7;;
		'!=') REPLY=7;;
		'<') REPLY=8;;
		'>') REPLY=8;;
		'<=') REPLY=8;;
		'>=') REPLY=8;;
		'<<') REPLY=9;;
		'>>') REPLY=9;;
		'+') REPLY=10;;
		'-') REPLY=10;;
		'*') REPLY=11;;
		'/') REPLY=11;;
		'%') REPLY=11;;
		'?') REPLY=0;;
		'-') REPLY=12;;
		'!') REPLY=12;;
		'~') REPLY=12;;
		'*') REPLY=12;;
		'&') REPLY=12;;
		'++') REPLY=12;;
		*) REPLY=0;;
	esac
}

c89_parser () {
	local CODE= STATE=Ca V=0 CONSUMED= STATES= NODES=" 0" X0="Ca" \
		NODE= PARN= PARNT= SIBL= REST= MATCH= _a= _W= _ST= _D= _C= _pq= \
		_EOF=0 _line= _PREV= _PLEN= _PLC=0 _JT=0 \
		_XC=0 _OP= _np=0 _cp=0 \
		_CMT_S='/*' _CMT_SL=2 _CMT_E='*/' _CMT_EL=2 \
		_LN=1 _COL=1 _RD=0

	while :; do
	    #echo "ОТЛАДКА: TOP OF LOOP: STATE=$STATE, CODE head=${CODE%% *}" >&2
		pars_progress
		ast_feed

		# --- Завершение выражения (подъем по приоритету) ---
		case $_XC in 1) _XC=0; case $STATE in C39|C55|C64|C66)
			case "$CODE" in ' '*|"$_TAB"*|"$_EOL"*) ast_skip_wse;; esac
			case "$CODE" in
			'-''>'*) CODE="${CODE#"->"}"; _COL=$((_COL+2)); ast_C61; _steal; continue;;
			'+''+'*) CODE="${CODE#"++"}"; _COL=$((_COL+2)); ast_C62; _steal; ast_close_xc;;
			'-''-'*) CODE="${CODE#"--"}"; _COL=$((_COL+2)); ast_C63; _steal; ast_close_xc;;
			'('*) CODE="${CODE#"("}"; _COL=$((_COL+1)); ast_C56; _steal; continue;;
			'['*) CODE="${CODE#"["}"; _COL=$((_COL+1)); ast_C58; _steal; continue;;
			'.'*) CODE="${CODE#"."}"; _COL=$((_COL+1)); ast_C60; _steal; continue;;
			esac
			_OP=
			case "$CODE" in
			'<''<''='*) _OP="<<="; _np=1;;
			'>''>''='*) _OP=">>="; _np=1;;
			'+''='*) _OP="+="; _np=1;;
			'-''='*) _OP="-="; _np=1;;
			'*''='*) _OP="*="; _np=1;;
			'/''='*) _OP="/="; _np=1;;
			'%''='*) _OP="%="; _np=1;;
			'&''='*) _OP="&="; _np=1;;
			'|''='*) _OP="|="; _np=1;;
			'^''='*) _OP="^="; _np=1;;
			'|''|'*) _OP="||"; _np=2;;
			'&''&'*) _OP="&&"; _np=3;;
			'=''='*) _OP="=="; _np=7;;
			'!''='*) _OP="!="; _np=7;;
			'<''='*) _OP="<="; _np=8;;
			'>''='*) _OP=">="; _np=8;;
			'<''<'*) _OP="<<"; _np=9;;
			'>''>'*) _OP=">>"; _np=9;;
			'='*) _OP="="; _np=1;;
			'|'*) _OP="|"; _np=4;;
			'^'*) _OP="^"; _np=5;;
			'&'*) _OP="&"; _np=6;;
			'<'*) _OP="<"; _np=8;;
			'>'*) _OP=">"; _np=8;;
			'+'*) _OP="+"; _np=10;;
			'-'*) _OP="-"; _np=10;;
			'*'*) _OP="*"; _np=11;;
			'/'*) _OP="/"; _np=11;;
			'%'*) _OP="%"; _np=11;;
			'?'*) _OP="?"; _np=0;;
			esac
			case "$_OP" in ?*)
				case $STATE in C55|C64|C66)
					_W="${NODES##*" "}"; eval "_W=\"\${V$_W:-}\""
					_c89_parser_prec "$_W"; _cp=$REPLY
					case "$_OP" in '='|'+='|'-='|'*='|'/='|'%='|'&='|'|='|'^='|'<<='|'>>='|'?') case $((_np < _cp)) in 1) ast_close_xc;; esac;;
					*) case $((_np <= _cp)) in 1) ast_close_xc;; esac;; esac
				;; esac
				ast_consume_op
				case "$_OP" in '?') ast_C64; _steal; continue;; esac
				ast_C55; _steal; continue
			;; esac
			case $STATE in C64) STATE=C65; continue;; esac
			case $STATE in C66) ast_close_xc;; esac
			case $STATE in C55) ast_close_xc;; esac
			case $STATE in C39) ast_close; _PREV=; continue;; esac
		;; esac;; esac

		# --- Быстрые пути (массовое накопление) ---
		case $STATE in
		# str: накопление (останавливается на закрывающей/экранированной)
		C45) case $CODE in '"'*|'\'*|'') ;; *)
			ast_more; REST="${CODE%%$_c89_sg_C45}"; ast_bulk_nl;; esac;;
		# chr: накопление (останавливается на закрывающей/экранированной)
		C46) case $CODE in "'"*|'\'*|'') ;; *)
			ast_more; REST="${CODE%%$_c89_sg_C46}"; ast_bulk_nl;; esac;;
		# number: накопление [0-9a-fA-FxXuUlL.]
		C47) ast_more; REST="${CODE%%[!0-9a-fA-FxXuUlL.]*}"
			case "$REST" in ?*) ast_bulk_nl;; *) ast_close; _XC=1; _PREV=; continue;; esac;;
		# ident: накопление [a-zA-Z_0-9]
		C48)
			_accum_utf8
			case "$MATCH" in
				?*)
					CONSUMED="$MATCH"
					_COL=$((_COL + ${#MATCH}))
					ast_close
					_XC=1
					_PREV=
					continue
					;;
				*)
					ast_close
					_XC=1
					_PREV=
					continue
					;;
			esac
			;;
		Cc|Cd|Ce|Cf|Cg|Ch|Ci|Cj|Ck|Cl|Cm|Cn|Co|Cp|Cq|Cr|Cs|Ct|Cu|Cv|Cw|Cx|Cy|Cz|C1|C2|C3|C4|C5|C6|C7|C8|C9|C10|C11|C12|C13|C14|C15|C16|C17|C18|C19|C20|C21|C22|C23|C24|C25|C26|C27|C28|C29|C31|C32|C33|C34|C35|C36|C37|C38|C39|C40|C41|C42|C43|C44|C49|C50|C51|C52|C53|C54|C55|C56|C57|C58|C59|C60|C61|C62|C63|C64|C65|C66|C67|C90|C93|C94|C95|C99|C101|C103|C104|C105|C106|C107|C115|C118|C120|C121|C124|C125|C127|C128|C129|C130|C132|C133|C134|C135|C136|C138|C140|C141|C142|C144|C145|C146|C147|C149|C150|C151|C152|C153|C154|C155|C156|C158|C159|C161|C163|C164|C165|C171|C173|C174|C175|C176|C177|C178)
			case $CODE in ' '*|"$_TAB"*|"$_EOL"*)
				ast_skip; continue;; esac;;
		esac

		# Пропуск блочного комментария
		case $CODE in '/*'*)
			ast_cmt_block;;
		esac

		# --- Диспетчеризация символов ---
		case $CODE in

		'"'*)
			case $STATE in
			C45) ast_close; ast_skip; continue;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc) STATE=C68; ast_C38; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C45; ast_skip; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C175|C177|Cd|Ce|Cf|Cg|Ch|Ci|Cj|Ck|Cl|Cm|Cn|Co|Cp|Cq|Cr|Cs|Ct|Cu|Cv|Cw|Cx|C90|Cz|C93|C2|C99|C101|C107|C115|C35|C42|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'\'*)
			case $STATE in
			C45)
				case ${CODE#?} in
				'"'*|'\'*|'/'*|'b'*|'f'*|'n'*|'r'*|'t'*)
					ast_consume2;;
				'u'*) case $CODE in
				'\u'[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]*)
						REST="${CODE#??????}"; _ast_xfer; _COL=$((_COL+6));;
					*) _error UNICODE;; esac;;
				*) _error ESCAPE;;
				esac; continue;;
			C46) ast_consume2; continue;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'WHILE') STATE=C68; ast_C28; ast_skip_match; continue;;
				*) ast_consume_match
					ast_C48; ast_close; STATE=C68; continue;;
				esac;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C67|C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C175|C177|Cc|Cd|Ce|Cf|Cg|Ch|Ci|Cj|Ck|Cl|Cm|Cn|Co|Cp|Cq|Cr|Cs|Ct|Cu|Cv|Cw|Cx|C90|Cz|C93|C2|C3|C99|C101|C107|C115|C21|C142|C147|C156|C159|C161|C35|C36|C37|C40|C42|C49|C50|C51|C52|C53|C54|C185|C186|C187|C188|C94|C105) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		"'"*)
			case $STATE in
			C46) ast_close; ast_skip; continue;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc) STATE=C68; ast_C38; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C46; ast_skip; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C175|C177|Cd|Ce|Cf|Cg|Ch|Ci|Cj|Ck|Cl|Cm|Cn|Co|Cp|Cq|Cr|Cs|Ct|Cu|Cv|Cw|Cx|C90|Cz|C93|C2|C99|C101|C107|C115|C35|C42|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'I'*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'INT') STATE=C68; ast_Cd; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'IF') STATE=C68; ast_C27; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C1) STATE=C94; ast_C8; continue;;
			C95) STATE=C94; ast_C8; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C8) STATE=C107; ast_C11; continue;;
			C11)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'INT') CONSUMED='int'; ast_skip_match
					ast_C11; ast_close; STATE=C111; continue;;
				*) ast_consume_match
					ast_C48; ast_close; STATE=C111; continue;;
				esac;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C94) STATE=C94; ast_C8; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'C'*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'CHAR') STATE=C68; ast_Ce; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'CONST') STATE=C68; ast_Cm; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'CONTINUE') STATE=C68; ast_C25; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'CASE') STATE=C68; ast_C32; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C1) STATE=C94; ast_C8; continue;;
			C95) STATE=C94; ast_C8; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C8) STATE=C107; ast_C11; continue;;
			C11)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'CHAR') CONSUMED='char'; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH}))
					ast_C11; ast_close; STATE=C111; continue;;
				'CONST') CONSUMED='const'; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH}))
					ast_C11; ast_close; STATE=C111; continue;;
				*) CONSUMED="$MATCH"; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH}))
					ast_C48; ast_close; STATE=C111; continue;;
				esac;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C94) STATE=C94; ast_C8; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'V'*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'VOID') STATE=C68; ast_Cf; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'VOLATILE') STATE=C68; ast_Cp; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C1) STATE=C94; ast_C8; continue;;
			C95) STATE=C94; ast_C8; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C8) STATE=C107; ast_C11; continue;;
			C11)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'VOID') CONSUMED='void'; ast_skip_match
					ast_C11; ast_close; STATE=C111; continue;;
				*) ast_consume_match
					ast_C48; ast_close; STATE=C111; continue;;
				esac;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C94) STATE=C94; ast_C8; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'L'*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'LONG') STATE=C68; ast_Cg; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C1) STATE=C94; ast_C8; continue;;
			C95) STATE=C94; ast_C8; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C8) STATE=C107; ast_C11; continue;;
			C11)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'LONG') CONSUMED='long'; ast_skip_match
					ast_C11; ast_close; STATE=C111; continue;;
				*) ast_consume_match
					ast_C48; ast_close; STATE=C111; continue;;
				esac;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C94) STATE=C94; ast_C8; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'S'*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'SHORT') STATE=C68; ast_Ch; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'SIGNED') STATE=C68; ast_Ck; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'STATIC') STATE=C68; ast_Cn; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'STRUCT') STATE=C68; ast_Ct; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'SWITCH') STATE=C68; ast_C31; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'SIZEOF') STATE=C68; ast_C34; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C1) STATE=C94; ast_C8; continue;;
			C95) STATE=C94; ast_C8; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C8) STATE=C107; ast_C11; continue;;
			C11)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'SHORT') CONSUMED='short'; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH}))
					ast_C11; ast_close; STATE=C111; continue;;
				'SIGNED') CONSUMED='signed'; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH}))
					ast_C11; ast_close; STATE=C111; continue;;
				'STRUCT') STATE=C111; ast_C12; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) CONSUMED="$MATCH"; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH}))
					ast_C48; ast_close; STATE=C111; continue;;
				esac;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'SIZEOF') STATE=C172; ast_C41; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C172; ast_C48; continue;;
				esac;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C94) STATE=C94; ast_C8; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'F'*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'FLOAT') STATE=C68; ast_Ci; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'FOR') STATE=C68; ast_C29; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C1) STATE=C94; ast_C8; continue;;
			C95) STATE=C94; ast_C8; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C8) STATE=C107; ast_C11; continue;;
			C11)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'FLOAT') CONSUMED='float'; ast_skip_match
					ast_C11; ast_close; STATE=C111; continue;;
				*) ast_consume_match
					ast_C48; ast_close; STATE=C111; continue;;
				esac;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C94) STATE=C94; ast_C8; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'D'*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'DOUBLE') STATE=C68; ast_Cj; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'DO') STATE=C68; ast_C30; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'DEFAULT') STATE=C68; ast_C33; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C1) STATE=C94; ast_C8; continue;;
			C95) STATE=C94; ast_C8; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C8) STATE=C107; ast_C11; continue;;
			C11)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'DOUBLE') CONSUMED='double'; ast_skip_match
					ast_C11; ast_close; STATE=C111; continue;;
				*) ast_consume_match
					ast_C48; ast_close; STATE=C111; continue;;
				esac;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C94) STATE=C94; ast_C8; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'U'*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'UNSIGNED') STATE=C68; ast_Cl; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'UNION') STATE=C68; ast_Cu; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C1) STATE=C94; ast_C8; continue;;
			C95) STATE=C94; ast_C8; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C8) STATE=C107; ast_C11; continue;;
			C11)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'UNSIGNED') CONSUMED='unsigned'; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH}))
					ast_C11; ast_close; STATE=C111; continue;;
				'UNION') STATE=C111; ast_C13; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) CONSUMED="$MATCH"; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH}))
					ast_C48; ast_close; STATE=C111; continue;;
				esac;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C94) STATE=C94; ast_C8; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'E'*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'EXTERN') STATE=C68; ast_Co; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'ENUM') STATE=C68; ast_Cv; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C1) STATE=C94; ast_C8; continue;;
			C95) STATE=C94; ast_C8; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C8) STATE=C107; ast_C11; continue;;
			C11)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'ENUM') STATE=C111; ast_C14; ast_skip_match; continue;;
				*) ast_consume_match
					ast_C48; ast_close; STATE=C111; continue;;
				esac;;
			C137) STATE=C138; ast_Cc; continue;;
			C138)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'ELSE') ast_skip_match; STATE=C139; continue;;
				*) ast_consume_match
					ast_C48; ast_close; continue;;
				esac;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C94) STATE=C94; ast_C8; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'A'*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'AUTO') STATE=C68; ast_Cq; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'R'*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'REGISTER') STATE=C68; ast_Cr; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'RETURN') STATE=C68; ast_C23; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'T'*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'TYPEDEF') STATE=C68; ast_Cs; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'B'*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'BREAK') STATE=C68; ast_C24; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'G'*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'GOTO') STATE=C68; ast_C26; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'#'*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc) STATE=C68; ast_C35; ast_skip; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C175|C177|Cd|Ce|Cf|Cg|Ch|Ci|Cj|Ck|Cl|Cm|Cn|Co|Cp|Cq|Cr|Cs|Ct|Cu|Cv|Cw|Cx|C90|Cz|C93|C2|C99|C101|C107|C115|C21|C35|C40|C42|C49|C50|C51|C52|C53|C54|C185|C186|C187|C188|C94|C105) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'{'*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc) STATE=C68; ast_C36; ast_skip; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			C93) STATE=C96; ast_C2; continue;;
			C2) STATE=C97; ast_C3; ast_skip; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C21) STATE=C131; ast_C22; ast_skip; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C175|C177|Cd|Ce|Cf|Cg|Ch|Ci|Cj|Ck|Cl|Cm|Cn|Co|Cp|Cq|Cr|Cs|Ct|Cu|Cw|Cx|C90|Cz|C99|C101|C107|C115|C35|C40|C42|C49|C50|C51|C52|C53|C54|C185|C186|C187|C188|C94|C105) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'+'*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc) STATE=C68; ast_C38; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C54; ast_skip; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C175|C177|Cd|Ce|Cf|Cg|Ch|Ci|Cj|Ck|Cl|Cm|Cn|Co|Cp|Cq|Cr|Cs|Ct|Cu|Cv|Cw|Cx|C90|Cz|C93|C2|C99|C101|C107|C115|C35|C42|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'&'*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc) STATE=C68; ast_C38; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C53; ast_skip; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C175|C177|Cd|Ce|Cf|Cg|Ch|Ci|Cj|Ck|Cl|Cm|Cn|Co|Cp|Cq|Cr|Cs|Ct|Cu|Cv|Cw|Cx|C90|Cz|C93|C2|C99|C101|C107|C115|C35|C42|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'*'*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc) STATE=C68; ast_C38; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Cw) STATE=C88; ast_Cx; ast_skip; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) ast_skip; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C10; ast_skip; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C17) STATE=C126; ast_C18; continue;;
			C18) ast_Cx; ast_skip; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C52; ast_skip; continue;;
			C175) ast_skip; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|Ct|Cu|Cv|C90|Cz|C93|C2|C99|C101|C35|C42|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'~'*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc) STATE=C68; ast_C38; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C51; ast_skip; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C175|C177|Cd|Ce|Cf|Cg|Ch|Ci|Cj|Ck|Cl|Cm|Cn|Co|Cp|Cq|Cr|Cs|Ct|Cu|Cv|Cw|Cx|C90|Cz|C93|C2|C99|C101|C107|C115|C35|C42|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'!'*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc) STATE=C68; ast_C38; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C50; ast_skip; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C175|C177|Cd|Ce|Cf|Cg|Ch|Ci|Cj|Ck|Cl|Cm|Cn|Co|Cp|Cq|Cr|Cs|Ct|Cu|Cv|Cw|Cx|C90|Cz|C93|C2|C99|C101|C107|C115|C35|C42|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'-'*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc) STATE=C68; ast_C38; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C49; ast_skip; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C175|C177|Cd|Ce|Cf|Cg|Ch|Ci|Cj|Ck|Cl|Cm|Cn|Co|Cp|Cq|Cr|Cs|Ct|Cu|Cv|Cw|Cx|C90|Cz|C93|C2|C99|C101|C107|C115|C35|C42|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'('*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc) STATE=C68; ast_C38; continue;;
			C90) STATE=C91; ast_Cz; continue;;
			Cz) STATE=C92; ast_C1; ast_skip; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C27) ast_skip; STATE=C135; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C28) ast_skip; STATE=C140; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C29) ast_skip; STATE=C144; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C150) ast_skip; STATE=C151; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C31) ast_skip; STATE=C154; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C34) ast_skip; STATE=C163; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C43; ast_skip; continue;;
			C41) ast_skip; STATE=C173; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C175|C177|Cd|Ce|Cf|Cg|Ch|Ci|Cj|Ck|Cl|Cm|Cn|Co|Cp|Cq|Cr|Cs|Ct|Cu|Cv|Cw|Cx|C93|C2|C99|C101|C107|C115|C35|C42|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'i'*)
		    #echo "DEBUG_i: Начало обработки, STATE=$STATE, _COL=$_COL, MATCH=$MATCH" >&2
			case $STATE in
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'INT') STATE=C68; ast_Cd; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'IF') STATE=C68; ast_C27; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C11)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'INT') CONSUMED='int'; ast_skip_match
					ast_C11; ast_close; STATE=C111; continue;;
				*) ast_consume_match
					ast_C48; ast_close; STATE=C111; continue;;
				esac;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			C1) STATE=C94; ast_C8; continue;;
			C95) STATE=C94; ast_C8; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C8) STATE=C107; ast_C11; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C94) STATE=C94; ast_C8; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'c'*)
			case $STATE in
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'CHAR') STATE=C68; ast_Ce; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'CONST') STATE=C68; ast_Cm; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'CONTINUE') STATE=C68; ast_C25; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'CASE') STATE=C68; ast_C32; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C11)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'CHAR') CONSUMED='char'; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH}))
					ast_C11; ast_close; STATE=C111; continue;;
				'CONST') CONSUMED='const'; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH}))
					ast_C11; ast_close; STATE=C111; continue;;
				*) CONSUMED="$MATCH"; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH}))
					ast_C48; ast_close; STATE=C111; continue;;
				esac;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			C1) STATE=C94; ast_C8; continue;;
			C95) STATE=C94; ast_C8; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C8) STATE=C107; ast_C11; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C94) STATE=C94; ast_C8; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'v'*)
			case $STATE in
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'VOID') STATE=C68; ast_Cf; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'VOLATILE') STATE=C68; ast_Cp; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C11)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'VOID') CONSUMED='void'; ast_skip_match
					ast_C11; ast_close; STATE=C111; continue;;
				*) ast_consume_match
					ast_C48; ast_close; STATE=C111; continue;;
				esac;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			C1) STATE=C94; ast_C8; continue;;
			C95) STATE=C94; ast_C8; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C8) STATE=C107; ast_C11; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C94) STATE=C94; ast_C8; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'l'*)
			case $STATE in
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'LONG') STATE=C68; ast_Cg; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C11)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'LONG') CONSUMED='long'; ast_skip_match
					ast_C11; ast_close; STATE=C111; continue;;
				*) ast_consume_match
					ast_C48; ast_close; STATE=C111; continue;;
				esac;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			C1) STATE=C94; ast_C8; continue;;
			C95) STATE=C94; ast_C8; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C8) STATE=C107; ast_C11; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C94) STATE=C94; ast_C8; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		's'*)
			case $STATE in
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'SHORT') STATE=C68; ast_Ch; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'SIGNED') STATE=C68; ast_Ck; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'STATIC') STATE=C68; ast_Cn; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'STRUCT') STATE=C68; ast_Ct; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'SWITCH') STATE=C68; ast_C31; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'SIZEOF') STATE=C68; ast_C34; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C11)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'SHORT') CONSUMED='short'; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH}))
					ast_C11; ast_close; STATE=C111; continue;;
				'SIGNED') CONSUMED='signed'; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH}))
					ast_C11; ast_close; STATE=C111; continue;;
				'STRUCT') STATE=C111; ast_C12; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) CONSUMED="$MATCH"; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH}))
					ast_C48; ast_close; STATE=C111; continue;;
				esac;;
			C40)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'SIZEOF') STATE=C172; ast_C41; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C172; ast_C48; continue;;
				esac;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			C1) STATE=C94; ast_C8; continue;;
			C95) STATE=C94; ast_C8; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C8) STATE=C107; ast_C11; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C55) ast_C40; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C94) STATE=C94; ast_C8; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'f'*)
			case $STATE in
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'FLOAT') STATE=C68; ast_Ci; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'FOR') STATE=C68; ast_C29; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C11)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'FLOAT') CONSUMED='float'; ast_skip_match
					ast_C11; ast_close; STATE=C111; continue;;
				*) ast_consume_match
					ast_C48; ast_close; STATE=C111; continue;;
				esac;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			C1) STATE=C94; ast_C8; continue;;
			C95) STATE=C94; ast_C8; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C8) STATE=C107; ast_C11; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C94) STATE=C94; ast_C8; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'd'*)
			case $STATE in
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'DOUBLE') STATE=C68; ast_Cj; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'DO') STATE=C68; ast_C30; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'DEFAULT') STATE=C68; ast_C33; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C11)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'DOUBLE') CONSUMED='double'; ast_skip_match
					ast_C11; ast_close; STATE=C111; continue;;
				*) ast_consume_match
					ast_C48; ast_close; STATE=C111; continue;;
				esac;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			C1) STATE=C94; ast_C8; continue;;
			C95) STATE=C94; ast_C8; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C8) STATE=C107; ast_C11; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C94) STATE=C94; ast_C8; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'u'*)
			case $STATE in
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'UNSIGNED') STATE=C68; ast_Cl; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'UNION') STATE=C68; ast_Cu; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C11)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'UNSIGNED') CONSUMED='unsigned'; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH}))
					ast_C11; ast_close; STATE=C111; continue;;
				'UNION') STATE=C111; ast_C13; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) CONSUMED="$MATCH"; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH}))
					ast_C48; ast_close; STATE=C111; continue;;
				esac;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			C1) STATE=C94; ast_C8; continue;;
			C95) STATE=C94; ast_C8; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C8) STATE=C107; ast_C11; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C94) STATE=C94; ast_C8; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'e'*)
			case $STATE in
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'EXTERN') STATE=C68; ast_Co; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				'ENUM') STATE=C68; ast_Cv; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C11)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'ENUM') STATE=C111; ast_C14; ast_skip_match; continue;;
				*) ast_consume_match
					ast_C48; ast_close; STATE=C111; continue;;
				esac;;
			C138)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'ELSE') ast_skip_match; STATE=C139; continue;;
				*) ast_consume_match
					ast_C48; ast_close; continue;;
				esac;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			C1) STATE=C94; ast_C8; continue;;
			C95) STATE=C94; ast_C8; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C8) STATE=C107; ast_C11; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C94) STATE=C94; ast_C8; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'a'*)
			case $STATE in
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'AUTO') STATE=C68; ast_Cq; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

			'r'*)
				case $STATE in
				
				# ============================================================
				# Состояние Cc: разбор ключевых слов и идентификаторов
				# ============================================================
				Cc)
					# Накопление слова (буквы, цифры, подчёркивание)
					ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
					# Преобразование в верхний регистр для сравнения
					_ucase "$MATCH"
					case "$REPLY" in
					'REGISTER') 
						# Ключевое слово register → создаём узел Cr, переходим в C68
						STATE=C68; ast_Cr; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
					'RETURN')
						# Ключевое слово return → создаём узел C23 (return_item)
						STATE=C68; ast_C23; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
					*)
						# Не ключевое слово → обрабатываем как идентификатор (C48)
						STATE=C68; ast_C38; continue;;
					esac;;
				
				# ============================================================
				# Состояние Cb: file_body (тело файла)
				# ============================================================
				Cb) STATE=C67; ast_Cc; continue;;
				
				# ============================================================
				# Состояние C67: ожидание выражения или оператора
				# ============================================================
				C67) ast_Cb; continue;;
				
				# ============================================================
				# Состояние C3: func_block (тело функции после {)
				# ============================================================
				C3) STATE=C98; ast_C37; continue;;
				
				# ============================================================
				# Состояния для обработки else (C137, C138, C139)
				# ============================================================
				C137) STATE=C138; ast_Cc; continue;;  # после else ожидаем ключевое слово/идентификатор
				C139) STATE=C138; ast_Cc; continue;;  # переход в C138
				
				# ============================================================
				# Состояния для обработки do-while (C142, C147)
				# ============================================================
				C142) STATE=C143; ast_Cc; continue;;  # после do ожидаем ключевое слово/идентификатор
				C147) STATE=C148; ast_Cc; continue;;
				
				# ============================================================
				# Состояние C30: do_item (тело do-while)
				# ============================================================
				C30) STATE=C149; ast_Cc; continue;;  # после тела do ожидаем while
				
				# ============================================================
				# Состояния для switch/case/default (C156, C159, C161)
				# ============================================================
				C156) STATE=C157; ast_Cc; continue;;
				C159) STATE=C160; ast_Cc; continue;;
				C161) STATE=C162; ast_Cc; continue;;
				
				# ============================================================
				# Состояния для блока (C36, C37, C169)
				# ============================================================
				C36) STATE=C167; ast_C37; continue;;  # открывающая {, переход в тело блока
				C37) STATE=C169; ast_Cc; continue;;   # внутри блока, ожидаем ключевое слово/идентификатор
				C169) STATE=C170; ast_C37; continue;; # закрывающая }
				
				# ============================================================
				# Состояние Ca: документ (корень)
				# ============================================================
				Ca) STATE=Ca; ast_Cb; continue;;      # начало файла, ожидаем объявления
				
				# ============================================================
				# Состояния для спецификаторов типов (Cd..Cs)
				# ============================================================
				Cd) STATE=C69; ast_Cw; continue;;     # int → ожидаем продолжение объявления
				Ce) STATE=C70; ast_Cw; continue;;     # char
				Cf) STATE=C71; ast_Cw; continue;;     # void
				Cg) STATE=C72; ast_Cw; continue;;     # long
				Ch) STATE=C73; ast_Cw; continue;;     # short
				Ci) STATE=C74; ast_Cw; continue;;     # float
				Cj) STATE=C75; ast_Cw; continue;;     # double
				Ck) STATE=C76; ast_Cw; continue;;     # signed
				Cl) STATE=C77; ast_Cw; continue;;     # unsigned
				Cm) STATE=C78; ast_Cw; continue;;     # const
				Cn) STATE=C79; ast_Cw; continue;;     # static
				Co) STATE=C80; ast_Cw; continue;;     # extern
				Cp) STATE=C81; ast_Cw; continue;;     # volatile
				Cq) STATE=C82; ast_Cw; continue;;     # auto
				Cr) STATE=C83; ast_Cw; continue;;     # register
				Cs) STATE=C84; ast_Cw; continue;;     # typedef
				
				# ============================================================
				# Состояния для struct/union/enum (Ct, Cu, Cv)
				# ============================================================
				Ct) STATE=C85; ast_C15; continue;;    # struct → ожидаем имя или {
				Cu) STATE=C86; ast_C15; continue;;    # union
				Cv) STATE=C87; ast_C16; continue;;    # enum
				
				# ============================================================
				# Состояния для указателей и объявлений (Cw, Cx, Cy)
				# ============================================================
				Cw) STATE=C88; ast_Cy; continue;;     # decl_rest
				Cx) STATE=C89; ast_Cw; continue;;     # ptr_decl (*)
				Cy) STATE=C90; ast_C48; continue;;    # ident_decl
				
				# ============================================================
				# Состояние C4: array_decl (объявление массива)
				# ============================================================
				C4) ast_C39; continue;;               # ожидаем выражение для размера
				
				# ============================================================
				# Состояние C5: init_part (= инициализатор)
				# ============================================================
				C5) STATE=C101; ast_C21; continue;;   # ожидаем инициализатор
				
				# ============================================================
				# Состояния для параметров функций (C103..C110)
				# ============================================================
				C103) STATE=C6; ast_C7; continue;;    # param
				C7) STATE=C104; ast_C48; continue;;   # ожидаем идентификатор параметра
				C105) ast_C39; continue;;             # выражение в параметре
				C106) STATE=C104; ast_C21; continue;; # инициализатор параметра
				C107) STATE=C108; ast_C9; continue;;  # param_rest (запятая)
				C9) STATE=C109; ast_C48; continue;;   # ожидаем следующий параметр
				C10) STATE=C110; ast_C9; continue;;   # param_ptr (*)
				
				# ============================================================
				# Состояния для struct/union/enum внутри объявлений (C12..C18)
				# ============================================================
				C12) STATE=C112; ast_C48; continue;;  # struct в объявлении
				C13) STATE=C113; ast_C48; continue;;  # union
				C14) STATE=C114; ast_C48; continue;;  # enum
				C15) STATE=C115; ast_C48; continue;;  # struct_rest
				C115) STATE=C116; ast_Cw; continue;;  # продолжение struct
				C16) STATE=C118; ast_C48; continue;;  # enum_vars
				C118) STATE=C119; ast_C17; continue;; # enum_rest
				C121) STATE=C122; ast_C18; continue;; # enumerator_list
				C17) STATE=C124; ast_C19; continue;;  # enum_tail
				C125) STATE=C126; ast_C18; continue;; # enum_vars продолжение
				C18) ast_Cy; continue;;               # завершение enum
				
				# ============================================================
				# Состояния для инициализаторов (C19, C20, C128, C129, C130)
				# ============================================================
				C19) STATE=C127; ast_C20; continue;;  # enumerator_list
				C128) STATE=C127; ast_C20; continue;; # следующий enumerator
				C20) STATE=C129; ast_C48; continue;;  # enumerator
				C130) STATE=C129; ast_C39; continue;; # = значение для enumerator
				C21) STATE=C131; ast_C39; continue;;  # initializer
				C22) STATE=C132; ast_C21; continue;;  # brace_init { ... }
				C133) STATE=C132; ast_C21; continue;; # продолжение brace_init
				
				# ============================================================
				# Состояние C23: return_item
				# ============================================================
				C23) ast_C39; continue;;              # после return ожидаем выражение
				
				# ============================================================
				# Состояние C26: goto_item
				# ============================================================
				C26) STATE=C134; ast_C48; continue;;  # после goto ожидаем метку
				
				# ============================================================
				# Состояния для if/while/for/do/switch (C135..C166)
				# ============================================================
				C135) STATE=C136; ast_C39; continue;; # после if( ожидаем условие
				C140) STATE=C141; ast_C39; continue;; # после while( ожидаем условие
				C144) ast_C39; continue;;             # после for( ожидаем выражение
				C145) ast_C39; continue;;             # после for(; ожидаем выражение
				C146) ast_C39; continue;;             # после for(;; ожидаем выражение
				C151) STATE=C152; ast_C39; continue;; # после do { ... } while( ожидаем условие
				C154) STATE=C155; ast_C39; continue;; # после switch( ожидаем выражение
				C32) STATE=C158; ast_C39; continue;;  # case: ожидаем выражение
				C163) STATE=C164; ast_C39; continue;; # sizeof( ожидаем выражение
				
				# ============================================================
				# Состояние C35: pp_line (препроцессор #)
				# ============================================================
				C35) STATE=C166; ast_C48; continue;;  # после # ожидаем директиву
				
				# ============================================================
				# Состояние C38: expr_item
				# ============================================================
				C38) STATE=C171; ast_C39; continue;;  # ожидаем выражение
				
				# ============================================================
				# Состояние C39: expr
				# ============================================================
				C39) ast_C40; continue;;              # разбор выражения
				
				# ============================================================
				# Состояние C40: atom (литералы, идентификаторы)
				# ============================================================
				C40) STATE=C172; ast_C48; continue;;  # ожидаем идентификатор или число
				
				# ============================================================
				# Состояния для sizeof (C173, C174, C175)
				# ============================================================
				C173) STATE=C174; ast_C42; continue;; # sizeof( тип )
				C42) STATE=C175; ast_C48; continue;;  # ожидаем имя типа
				C175) ast_C48; continue;;             # ожидаем идентификатор
				
				# ============================================================
				# Состояния для скобок и вызовов (C43, C44, C178)
				# ============================================================
				C43) STATE=C176; ast_C39; continue;;  # ( выражение )
				C44) STATE=C177; ast_C39; continue;;  # аргументы функции
				C178) STATE=C177; ast_C39; continue;; # продолжение аргументов
				
				# ============================================================
				# Состояния для унарных операторов (C49..C54)
				# ============================================================
				C49) STATE=C179; ast_C40; continue;;  # унарный -
				C50) STATE=C180; ast_C40; continue;;  # унарный !
				C51) STATE=C181; ast_C40; continue;;  # унарный ~
				C52) STATE=C182; ast_C40; continue;;  # унарный *
				C53) STATE=C183; ast_C40; continue;;  # унарный &
				C54) STATE=C184; ast_C40; continue;;  # ++ (префиксный)
				
				# ============================================================
				# Состояние C55: бинарный оператор
				# ============================================================
				C55) ast_C40; continue;;              # ожидаем операнд
				
				# ============================================================
				# Состояния для постфиксных операторов (C56, C58, C60, C61, C64, C66)
				# ============================================================
				C56) STATE=C57; ast_C44; continue;;   # вызов функции (
				C58) STATE=C59; ast_C39; continue;;   # индексация массива [
				C60) STATE=C185; ast_C48; continue;;  # доступ к полю .
				C61) STATE=C186; ast_C48; continue;;  # доступ к полю ->
				C64) ast_C40; continue;;              # тернарный оператор ?
				C66) ast_C40; continue;;              # после : в тернарном операторе
				
				# ============================================================
				# Завершающие состояния (закрытие узлов AST)
				# ============================================================
				C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188|C94) 
					ast_close_col_xc;;                # закрыть узел и продолжить подъём по приоритету
				
				C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) 
					ast_close_xc;;                   # закрыть узел и выйти из подъёма по приоритету
				
				# ============================================================
				# Если состояние не найдено — ошибка
				# ============================================================
				*) _pars_err;;
				esac;;

		't'*)
			case $STATE in
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'TYPEDEF') STATE=C68; ast_Cs; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'b'*)
			case $STATE in
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'BREAK') STATE=C68; ast_C24; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'g'*)
			case $STATE in
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'GOTO') STATE=C68; ast_C26; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'w'*)
			case $STATE in
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'WHILE') STATE=C68; ast_C28; CODE="${CODE#"$MATCH"}"; _COL=$((_COL+${#MATCH})); continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C149)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'WHILE') ast_skip_match; STATE=C150; continue;;
				*) ast_consume_match
					ast_C48; ast_close; continue;;
				esac;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		';'*)
			case $STATE in
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Cw) ast_Cw; ast_skip; ast_close; STATE=C88; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			C90) STATE=C91; ast_Cz; continue;;
			Cz) STATE=C92; ast_C6; continue;;
			C93) STATE=C96; ast_C2; continue;;
			C2) STATE=C97; ast_C6; continue;;
			C99) STATE=C100; ast_C6; continue;;
			C101) STATE=C102; ast_C6; continue;;
			C6) ast_skip; ast_close; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C17) STATE=C126; ast_C18; continue;;
			C18) ast_Cw; ast_skip; ast_close; continue;;
			C23) ast_skip; ast_close; continue;;
			C24) ast_skip; ast_close; continue;;
			C25) ast_skip; ast_close; continue;;
			C134) ast_skip; ast_close; continue;;
			C144) ast_skip; STATE=C145; continue;;
			C145) ast_skip; STATE=C146; continue;;
			C153) ast_skip; ast_close; continue;;
			C165) ast_skip; ast_close; continue;;
			C171) ast_skip; ast_close; continue;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'WHILE') STATE=C68; ast_C28; ast_skip_match; continue;;
				*) ast_consume_match
					ast_C48; ast_close; STATE=C68; continue;;
				esac;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C67|C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C175|C177|Cc|Ct|Cu|Cv|C3|C107|C21|C142|C147|C156|C159|C161|C35|C36|C37|C40|C42|C49|C50|C51|C52|C53|C54|C185|C186|C187|C188|C94|C105) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'['*)
			case $STATE in
			C90) STATE=C91; ast_Cz; continue;;
			Cz) STATE=C92; ast_C4; ast_skip; continue;;
			C104) ast_skip; STATE=C105; continue;;
			C105) ast_skip; STATE=C105; continue;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'WHILE') STATE=C68; ast_C28; ast_skip_match; continue;;
				*) ast_consume_match
					ast_C48; ast_close; STATE=C68; continue;;
				esac;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C67|C68|C88|C91|C92|C97|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C175|C177|Cc|Cd|Ce|Cf|Cg|Ch|Ci|Cj|Ck|Cl|Cm|Cn|Co|Cp|Cq|Cr|Cs|Ct|Cu|Cv|Cw|Cx|C93|C2|C3|C99|C101|C107|C115|C21|C142|C147|C156|C159|C161|C35|C36|C37|C40|C42|C49|C50|C51|C52|C53|C54|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'='*)
			case $STATE in
			C90) STATE=C91; ast_Cz; continue;;
			Cz) STATE=C92; ast_C5; ast_skip; continue;;
			C104) ast_skip; STATE=C106; continue;;
			C129) ast_skip; STATE=C130; continue;;
			C105) ast_skip; STATE=C106; continue;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'WHILE') STATE=C68; ast_C28; ast_skip_match; continue;;
				*) ast_consume_match
					ast_C48; ast_close; STATE=C68; continue;;
				esac;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C67|C68|C88|C91|C92|C97|C108|C109|C111|C116|C117|C119|C123|C127|C131|C138|C168|C170|C172|C175|C177|Cc|Cd|Ce|Cf|Cg|Ch|Ci|Cj|Ck|Cl|Cm|Cn|Co|Cp|Cq|Cr|Cs|Ct|Cu|Cv|Cw|Cx|C93|C2|C3|C99|C101|C107|C115|C21|C142|C147|C156|C159|C161|C35|C36|C37|C40|C42|C49|C50|C51|C52|C53|C54|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		','*)
			case $STATE in
			C90) STATE=C91; ast_Cz; continue;;
			Cz) STATE=C92; ast_C6; continue;;
			C94) ast_skip; STATE=C95; continue;;
			C93) STATE=C96; ast_C2; continue;;
			C2) STATE=C97; ast_C6; continue;;
			C99) STATE=C100; ast_C6; continue;;
			C101) STATE=C102; ast_C6; continue;;
			C6) ast_skip; STATE=C103; continue;;
			C127) ast_skip; STATE=C128; continue;;
			C132) ast_skip; STATE=C133; continue;;
			C177) ast_skip; STATE=C178; continue;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'WHILE') STATE=C68; ast_C28; ast_skip_match; continue;;
				*) ast_consume_match
					ast_C48; ast_close; STATE=C68; continue;;
				esac;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C67|C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C129|C131|C138|C168|C170|C172|C175|Cc|Cd|Ce|Cf|Cg|Ch|Ci|Cj|Ck|Cl|Cm|Cn|Co|Cp|Cq|Cr|Cs|Ct|Cu|Cv|Cw|Cx|C3|C107|C115|C21|C142|C147|C156|C159|C161|C35|C36|C37|C40|C42|C49|C50|C51|C52|C53|C54|C185|C186|C187|C188|C105) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		')'*)
			case $STATE in
			C1) ast_skip; STATE=C93; continue;;
			C136) ast_skip; STATE=C137; continue;;
			C141) ast_skip; STATE=C142; continue;;
			C146) ast_skip; STATE=C147; continue;;
			C152) ast_skip; STATE=C153; continue;;
			C155) ast_skip; STATE=C156; continue;;
			C164) ast_skip; STATE=C165; continue;;
			C174) ast_skip; ast_close; continue;;
			C176) ast_skip; ast_close; continue;;
			C56) ast_skip; ast_close_xc;;
			C57) ast_skip; ast_close_xc;;
			C94) ast_skip; STATE=C93; continue;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'WHILE') STATE=C68; ast_C28; ast_skip_match; continue;;
				*) ast_consume_match
					ast_C48; ast_close; STATE=C68; continue;;
				esac;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C67|C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C175|C177|Cc|Cd|Ce|Cf|Cg|Ch|Ci|Cj|Ck|Cl|Cm|Cn|Co|Cp|Cq|Cr|Cs|Ct|Cu|Cv|Cw|Cx|C90|Cz|C93|C2|C3|C99|C101|C107|C115|C21|C142|C147|C156|C159|C161|C35|C36|C37|C40|C42|C49|C50|C51|C52|C53|C54|C185|C186|C187|C188|C105) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'}'*)
			case $STATE in
			C3) STATE=C98; ast_C37; continue;;
			C120) ast_skip; STATE=C121; continue;;
			C124) ast_skip; STATE=C125; continue;;
			C132) ast_skip; ast_close; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) ast_C37; ast_skip; ast_close; STATE=C168; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'WHILE') STATE=C68; ast_C28; ast_skip_match; continue;;
				*) ast_consume_match
					ast_C48; ast_close; STATE=C68; continue;;
				esac;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C67|C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C175|C177|Cc|Cd|Ce|Cf|Cg|Ch|Ci|Cj|Ck|Cl|Cm|Cn|Co|Cp|Cq|Cr|Cs|Ct|Cu|Cv|Cw|Cx|C90|Cz|C93|C2|C99|C101|C107|C115|C21|C142|C147|C156|C159|C161|C35|C40|C42|C49|C50|C51|C52|C53|C54|C185|C186|C187|C188|C94|C105) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		']'*)
			case $STATE in
			C4) ast_skip; STATE=C99; continue;;
			C105) ast_skip; STATE=C104; continue;;
			C58) ast_skip; ast_close_xc;;
			C59) ast_skip; ast_close_xc;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'WHILE') STATE=C68; ast_C28; ast_skip_match; continue;;
				*) ast_consume_match
					ast_C48; ast_close; STATE=C68; continue;;
				esac;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C67|C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C175|C177|Cc|Cd|Ce|Cf|Cg|Ch|Ci|Cj|Ck|Cl|Cm|Cn|Co|Cp|Cq|Cr|Cs|Ct|Cu|Cv|Cw|Cx|C90|Cz|C93|C2|C3|C99|C101|C107|C115|C21|C142|C147|C156|C159|C161|C35|C36|C37|C40|C42|C49|C50|C51|C52|C53|C54|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'W'*)
			case $STATE in
			C149)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'WHILE') ast_skip_match; STATE=C150; continue;;
				*) ast_consume_match
					ast_C48; ast_close; continue;;
				esac;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc) STATE=C68; ast_C38; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		':'*)
			case $STATE in
			C158) ast_skip; STATE=C159; continue;;
			C33) ast_skip; STATE=C161; continue;;
			C65) ast_skip; STATE=C66; continue;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'WHILE') STATE=C68; ast_C28; ast_skip_match; continue;;
				*) ast_consume_match
					ast_C48; ast_close; STATE=C68; continue;;
				esac;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C67|C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C175|C177|Cc|Cd|Ce|Cf|Cg|Ch|Ci|Cj|Ck|Cl|Cm|Cn|Co|Cp|Cq|Cr|Cs|Ct|Cu|Cv|Cw|Cx|C90|Cz|C93|C2|C3|C99|C101|C107|C115|C21|C142|C147|C156|C159|C161|C35|C36|C37|C40|C42|C49|C50|C51|C52|C53|C54|C185|C186|C187|C188|C94|C105) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		#---РУССКИЕ ИДЕНТИФИКАТОРЫ---

		#ВЕРНУТЬ  (extern	  внешний   ???????)
		'в'*|'В'*)
			case $STATE in
			Cc)
				_accum_utf8
				_ucase "$MATCH"
				case "$REPLY" in
				'REGISTER') STATE=C68; ast_Cr; continue;;
				'RETURN'|'ВЕРНУТЬ') STATE=C68; ast_C23; continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C3) STATE=C98; ast_C37; continue;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;	


		'е'*|'Е'*)
			case $STATE in
			Cc)
				_accum_utf8
				_ucase "$MATCH"
				case "$REPLY" in
				'ЕСЛИ') STATE=C68; ast_C27; continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;


		'з'*|'З'*)
			case $STATE in
			Cc)
				_accum_utf8
				_ucase "$MATCH"
				case "$REPLY" in
				'ЗАПУСК') STATE=C68; ast_C38; continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;	


		'и'*|'И'*)
			case $STATE in
			Cc)
				_accum_utf8
				_ucase "$MATCH"
				case "$REPLY" in
				'ИНАЧЕ') STATE=C68; ast_C38; continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C138)
				_accum_utf8
				_ucase "$MATCH"
				case "$REPLY" in
				'ИНАЧЕ') ast_skip_match; STATE=C139; continue;;
				*) ast_consume_match
					ast_C48; ast_close; continue;;
				esac;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;


		# 'а'*|'А'*)  РАБОЧАЯ
		#     # Минимальная секция - просто игнорируем слова на букву а
		#     continue;;

		# 'б'*|'Б'*)  РАБОЧАЯ
		#     continue;;

		# 'в'*|'В'*)  РАБОЧАЯ
		#     continue;;

		# 'г'*|'Г'*)  РАБОЧАЯ
		#     continue;;

		# 'д'*|'Д'*)  РАБОЧАЯ
		#     continue;;

		# 'е'*|'Е'*)-------------------------ЕСЛИ
		#     continue;;

		# 'ё'*|'Ё'*)  РАБОЧАЯ
		#     continue;;

		# 'ж'*|'Ж'*)  РАБОЧАЯ
		#     continue;;

		# 'з'*|'З'*)  РАБОЧАЯ
		#     continue;;

		# 'и'*|'И'*)--------------------------ИНАЧЕ
		#     continue;;

		# 'й'*|'Й'*)  РАБОЧАЯ
		#     continue;;

		# 'к'*|'К'*)  РАБОЧАЯ
		#     continue;;

		# 'л'*|'Л'*)  РАБОЧАЯ
		#     continue;;

		# 'м'*|'М'*)          БАГУЕТ
		#     continue;;

		# 'н'*|'Н'*)  РАБОЧАЯ
		#     continue;;

		# 'о'*|'О'*)  РАБОЧАЯ
		#     continue;;

		# 'п'*|'П'*)          БАГУЕТ
		#     continue;;

		# 'р'*|'Р'*)          БАГУЕТ
		#     continue;;

		# 'с'*|'С'*)          БАГУЕТ
		#     continue;;

		# 'т'*|'Т'*)          БАГУЕТ
		#     continue;;

		# 'у'*|'У'*)          БАГУЕТ
		#     continue;;

		# 'ф'*|'Ф'*)  РАБОЧАЯ    
		#     continue;;

		# 'х'*|'Х'*)  РАБОЧАЯ  
		#     continue;;

		# 'ц'*|'Ц'*)-------------------------ЦЕЛ
		#     continue;;

		# 'ч'*|'Ч'*)          БАГУЕТ
		#     continue;;

		# 'ш'*|'Ш'*)  РАБОЧАЯ  
		#     continue;;

		# 'щ'*|'Щ'*)  РАБОЧАЯ 
		#     continue;;

		# 'ъ'*|'Ъ'*)  РАБОЧАЯ 
		#     continue;;

		# 'ы'*|'Ы'*)  РАБОЧАЯ 
		#     continue;;

		# 'ь'*|'Ь'*)  РАБОЧАЯ 
		#     continue;;

		# 'э'*|'Э'*)  РАБОЧАЯ 
		#     continue;;

		# 'ю'*|'Ю'*)  РАБОЧАЯ 
		#     continue;;

		# 'я'*|'Я'*)  РАБОЧАЯ 
		#     continue;;


		'о'*|'О'*)
			case $STATE in
			Cc)
				_accum_utf8
				_ucase "$MATCH"
				case "$REPLY" in
				'ОВЗ') STATE=C68; ast_Cf; continue;; # void - отсутствие возвращаемого знаения
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C11)
				_accum_utf8
				_ucase "$MATCH"
				case "$REPLY" in
				'ОВЗ') CONSUMED='void'; ast_Cf; ast_close; STATE=C111; continue;;
				*) CONSUMED="$MATCH"; ast_C48; ast_close; STATE=C111; continue;;
				esac;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C94) STATE=C94; ast_C8; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;



		'ц'*|'Ц'*)
		    #echo "ОТЛАДКА_ц: Начало обработки, STATE=$STATE, _COL=$_COL, MATCH=$MATCH" >&2
			#echo "ОТЛАДКА_ц: FIRST CHAR='${CODE%% *}'" >&2
			case $STATE in
			C1)
				#echo "ОТЛАДКА_ц: C1 -> C94, ast_C8" >&2
				STATE=C94; ast_C8; continue;;
			C8)
				#echo "ОТЛАДКА_ц: C8 -> C107, ast_C11" >&2
				STATE=C107; ast_C11; continue;;
			Cc)
				_accum_utf8
				_ucase "$MATCH"
				case "$REPLY" in
				'ЦЕЛ') STATE=C68; ast_Cd; continue;;
				'ЦП') STATE=C68; ast_C28; continue;;
				*) STATE=C68; ast_C38; continue;;
				esac;;
			C11)
				#echo "ОТЛАДКА_ц: C11: before _accum_utf8, CODE head=${CODE%% *}" >&2
				_accum_utf8
				#echo "ОТЛАДКА_ц: C11: after _accum_utf8, MATCH='$MATCH', CODE head=${CODE%% *}" >&2
				_ucase "$MATCH"
				#echo "ОТЛАДКА_ц: C11: after _ucase, REPLY='$REPLY'" >&2
				case "$REPLY" in
				'ЦЕЛ') CONSUMED='int'; ast_Cd; ast_close; STATE=C111; continue;;
				*) CONSUMED="$MATCH"; ast_C48; ast_close; STATE=C111; continue;;
				esac;;
			C95)
				#echo "ОТЛАДКА_ц: C95 -> C94, ast_C8" >&2
				STATE=C94; ast_C8; continue;;
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C94) STATE=C94; ast_C8; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		
		
		#ПЕРЕМЕННЫЕ НА КИРИЛЛИЦЕ НУЖНЫ ЕЩЕ
		[a-zA-Z_а-яА-Я_0-90-9a-fA-FxXuUlL.]*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc) STATE=C68; ast_C38; continue;;
			Cd) STATE=C69; ast_Cw; continue;;
			Ce) STATE=C70; ast_Cw; continue;;
			Cf) STATE=C71; ast_Cw; continue;;
			Cg) STATE=C72; ast_Cw; continue;;
			Ch) STATE=C73; ast_Cw; continue;;
			Ci) STATE=C74; ast_Cw; continue;;
			Cj) STATE=C75; ast_Cw; continue;;
			Ck) STATE=C76; ast_Cw; continue;;
			Cl) STATE=C77; ast_Cw; continue;;
			Cm) STATE=C78; ast_Cw; continue;;
			Cn) STATE=C79; ast_Cw; continue;;
			Co) STATE=C80; ast_Cw; continue;;
			Cp) STATE=C81; ast_Cw; continue;;
			Cq) STATE=C82; ast_Cw; continue;;
			Cr) STATE=C83; ast_Cw; continue;;
			Cs) STATE=C84; ast_Cw; continue;;
			Ct) STATE=C85; ast_C15; continue;;
			Cu) STATE=C86; ast_C15; continue;;
			Cv) STATE=C87; ast_C16; continue;;
			Cw) STATE=C88; ast_Cy; continue;;
			Cx) STATE=C89; ast_Cw; continue;;
			Cy) STATE=C90; ast_C48; continue;;
			C3) STATE=C98; ast_C37; continue;;
			C4) ast_C39; continue;;
			C5) STATE=C101; ast_C21; continue;;
			C103) STATE=C6; ast_C7; continue;;
			C7) STATE=C104; ast_C48; continue;;
			C105) ast_C39; continue;;
			C106) STATE=C104; ast_C21; continue;;
			C107) STATE=C108; ast_C9; continue;;
			C9) STATE=C109; ast_C48; continue;;
			C10) STATE=C110; ast_C9; continue;;
			C12) STATE=C112; ast_C48; continue;;
			C13) STATE=C113; ast_C48; continue;;
			C14) STATE=C114; ast_C48; continue;;
			C15) STATE=C115; ast_C48; continue;;
			C115) STATE=C116; ast_Cw; continue;;
			C16) STATE=C118; ast_C48; continue;;
			C118) STATE=C119; ast_C17; continue;;
			C121) STATE=C122; ast_C18; continue;;
			C17) STATE=C124; ast_C19; continue;;
			C125) STATE=C126; ast_C18; continue;;
			C18) ast_Cy; continue;;
			C19) STATE=C127; ast_C20; continue;;
			C128) STATE=C127; ast_C20; continue;;
			C20) STATE=C129; ast_C48; continue;;
			C130) STATE=C129; ast_C39; continue;;
			C21) STATE=C131; ast_C39; continue;;
			C22) STATE=C132; ast_C21; continue;;
			C133) STATE=C132; ast_C21; continue;;
			C23) ast_C39; continue;;
			C26) STATE=C134; ast_C48; continue;;
			C135) STATE=C136; ast_C39; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C140) STATE=C141; ast_C39; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C144) ast_C39; continue;;
			C145) ast_C39; continue;;
			C146) ast_C39; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C151) STATE=C152; ast_C39; continue;;
			C154) STATE=C155; ast_C39; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C32) STATE=C158; ast_C39; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C163) STATE=C164; ast_C39; continue;;
			C35) STATE=C166; ast_C48; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			C38) STATE=C171; ast_C39; continue;;
			C39) ast_C40; continue;;
			C40) STATE=C172; ast_C48; continue;;
			C173) STATE=C174; ast_C42; continue;;
			C42) STATE=C175; ast_C48; continue;;
			C175) ast_C48; continue;;
			C43) STATE=C176; ast_C39; continue;;
			C44) STATE=C177; ast_C39; continue;;
			C178) STATE=C177; ast_C39; continue;;
			C49) STATE=C179; ast_C40; continue;;
			C50) STATE=C180; ast_C40; continue;;
			C51) STATE=C181; ast_C40; continue;;
			C52) STATE=C182; ast_C40; continue;;
			C53) STATE=C183; ast_C40; continue;;
			C54) STATE=C184; ast_C40; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C55) ast_C40; continue;;
			C56) STATE=C57; ast_C44; continue;;
			C58) STATE=C59; ast_C39; continue;;
			C60) STATE=C185; ast_C48; continue;;
			C61) STATE=C186; ast_C48; continue;;
			C64) ast_C40; continue;;
			C66) ast_C40; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C177|C90|Cz|C93|C2|C99|C101|C185|C186|C187|C188|C94) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;

		'')
			case $STATE in
			C67|C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C175|C177|Cc|Cd|Ce|Cf|Cg|Ch|Ci|Cj|Ck|Cl|Cm|Cn|Co|Cp|Cq|Cr|Cs|Ct|Cu|Cv|Cw|Cx|C90|Cz|C93|C2|C3|C99|C101|C107|C115|C21|C142|C147|C156|C159|C161|C35|C36|C37|C40|C42|C49|C50|C51|C52|C53|C54|C185|C186|C187|C188|C94|C105) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			C55) ast_close; continue;;
			C39) ast_close; continue;;
			Ca) break;;
			*) _pars_err_eof;;
			esac;;

		*)
			case $STATE in
			Cb) STATE=C67; ast_Cc; continue;;
			C67) ast_Cb; continue;;
			Cc)
				ast_more; MATCH="${CODE%%[!a-zA-Z0-9_]*}"
				_ucase "$MATCH"
				case "$REPLY" in
				'WHILE') STATE=C68; ast_C28; ast_skip_match; continue;;
				*) ast_consume_match
					ast_C48; ast_close; STATE=C68; continue;;
				esac;;
			C3) STATE=C98; ast_C37; continue;;
			C137) STATE=C138; ast_Cc; continue;;
			C139) STATE=C138; ast_Cc; continue;;
			C142) STATE=C143; ast_Cc; continue;;
			C147) STATE=C148; ast_Cc; continue;;
			C30) STATE=C149; ast_Cc; continue;;
			C156) STATE=C157; ast_Cc; continue;;
			C159) STATE=C160; ast_Cc; continue;;
			C161) STATE=C162; ast_Cc; continue;;
			C36) STATE=C167; ast_C37; continue;;
			C37) STATE=C169; ast_Cc; continue;;
			C169) STATE=C170; ast_C37; continue;;
			Ca) STATE=Ca; ast_Cb; continue;;
			C68|C88|C91|C92|C97|C104|C108|C109|C111|C116|C117|C119|C123|C127|C129|C131|C138|C168|C170|C172|C175|C177|Cd|Ce|Cf|Cg|Ch|Ci|Cj|Ck|Cl|Cm|Cn|Co|Cp|Cq|Cr|Cs|Ct|Cu|Cv|Cw|Cx|C90|Cz|C93|C2|C99|C101|C107|C115|C21|C35|C40|C42|C49|C50|C51|C52|C53|C54|C185|C186|C187|C188|C94|C105) ast_close_col_xc;;
			C69|C70|C71|C72|C73|C74|C75|C76|C77|C78|C79|C80|C81|C82|C83|C84|C85|C86|C87|C89|C96|C98|C100|C102|C110|C112|C113|C114|C122|C126|C143|C148|C157|C160|C162|C166|C167|C179|C180|C181|C182|C183|C184) ast_close_xc;;
			*) _pars_err;;
			esac;;
		esac
	done

	ast_out
}

# --- modules/c89/unast.sh ---


# --- Эмиттер (реконструкция исходного кода из AST) ---

_c89_unast_emit () {
	local _n=$1 _t _v _r _ch
	IFS=' '; eval "set -- \$X$_n"; IFS=''
	_t=$1; shift
	eval "_v=\"\${V$_n:-}\""

	case "$_t" in
	Ca) _r=
		for _ch in "$@"; do
			case "$_r" in ?*) _r="$_r$_EOL";; esac
			_c89_unast_emit "$_ch"; _r="$_r$REPLY"
		done; REPLY="$_r";;
	Cb) _c89_unast_emit "$1"; _r="$REPLY"
		shift 1
		_si=1
		case $# in 0) ;; *) _c89_unast_emit "$1"; _r="${_r} $REPLY"; shift;; esac
		REPLY="${_r}";;
	Cc) case $# in 0) REPLY="$_v";; 1) _c89_unast_emit "$1";; *) _r=; for _ch in "$@"; do _c89_unast_emit "$_ch"; _r="$_r$REPLY"; done; REPLY="$_r";; esac;;
	Cd) _c89_unast_emit "$1"; REPLY="int ${REPLY}";;
	Ce) _c89_unast_emit "$1"; REPLY="char ${REPLY}";;
	Cf) _c89_unast_emit "$1"; REPLY="void ${REPLY}";;
	Cg) _c89_unast_emit "$1"; REPLY="long ${REPLY}";;
	Ch) _c89_unast_emit "$1"; REPLY="short ${REPLY}";;
	Ci) _c89_unast_emit "$1"; REPLY="float ${REPLY}";;
	Cj) _c89_unast_emit "$1"; REPLY="double ${REPLY}";;
	Ck) _c89_unast_emit "$1"; REPLY="signed ${REPLY}";;
	Cl) _c89_unast_emit "$1"; REPLY="unsigned ${REPLY}";;
	Cm) _c89_unast_emit "$1"; REPLY="const ${REPLY}";;
	Cn) _c89_unast_emit "$1"; REPLY="static ${REPLY}";;
	Co) _c89_unast_emit "$1"; REPLY="extern ${REPLY}";;
	Cp) _c89_unast_emit "$1"; REPLY="volatile ${REPLY}";;
	Cq) _c89_unast_emit "$1"; REPLY="auto ${REPLY}";;
	Cr) _c89_unast_emit "$1"; REPLY="register ${REPLY}";;
	Cs) _c89_unast_emit "$1"; REPLY="typedef ${REPLY}";;
	Ct) _c89_unast_emit "$1"; REPLY="struct ${REPLY}";;
	Cu) _c89_unast_emit "$1"; REPLY="union ${REPLY}";;
	Cv) _c89_unast_emit "$1"; REPLY="enum ${REPLY}";;
	Cw) case $# in 0) case "$_v" in ?*) REPLY="$_v";; *) REPLY=";";; esac;; 1) _c89_unast_emit "$1";; *) _r=; for _ch in "$@"; do _c89_unast_emit "$_ch"; _r="$_r$REPLY"; done; REPLY="$_r";; esac;;
	Cx) _c89_unast_emit "$1"; REPLY="*${REPLY}";;
	Cy) _c89_unast_emit "$1"; _r="$REPLY"
		_c89_unast_emit "$2"; REPLY="${_r} ${REPLY}";;
	Cz) case $# in 0) case "$_v" in ?*) REPLY="$_v";; *) REPLY=";";; esac;; 1) _c89_unast_emit "$1";; *) _r=; for _ch in "$@"; do _c89_unast_emit "$_ch"; _r="$_r$REPLY"; done; REPLY="$_r";; esac;;
	C1) _r="("
		while test $# -gt 1; do
			case "$_r" in "(") ;; *) _r="$_r,";; esac
			_c89_unast_emit "$1"; _r="$_r$REPLY"; shift
		done
		_r="$_r)"
		_c89_unast_emit "$1"; REPLY="$_r${REPLY}";;
	C2) case $# in 0) REPLY="$_v";; 1) _c89_unast_emit "$1";; *) _r=; for _ch in "$@"; do _c89_unast_emit "$_ch"; _r="$_r$REPLY"; done; REPLY="$_r";; esac;;
	C3) _c89_unast_emit "$1"; REPLY="{${REPLY}";;
	C4) _r="["
		case $# in 0) ;; *) _c89_unast_emit "$1"; _r="${_r}$REPLY"; shift;; esac
		_si=1
		case $# in 0) ;; *) _c89_unast_emit "$1"; _r="${_r}]$REPLY"; shift;; esac
		case $# in 0) ;; *) _c89_unast_emit "$1"; _r="${_r} $REPLY"; shift;; esac
		REPLY="${_r}";;
	C5) _c89_unast_emit "$1"; _r="=$REPLY"
		_c89_unast_emit "$2"; REPLY="${_r} ${REPLY}";;
	C6) _r=""
		for _ch in "$@"; do
			case "$_r" in "") ;; *) _r="$_r,";; esac
			_c89_unast_emit "$_ch"; _r="$_r$REPLY"
		done; REPLY="$_r;";;
	C7) _r=""
		while test $# -gt 3; do
			case "$_r" in "") ;; *) _r="$_r ";; esac
			_c89_unast_emit "$1"; _r="$_r$REPLY"; shift
		done
		_c89_unast_emit "$1"; REPLY="$_r${REPLY}";;
	C8) _c89_unast_emit "$1"; _r="$REPLY"
		_c89_unast_emit "$2"; REPLY="${_r} ${REPLY}";;
	C9) case $# in 0) REPLY="$_v";; 1) _c89_unast_emit "$1";; *) _r=; for _ch in "$@"; do _c89_unast_emit "$_ch"; _r="$_r$REPLY"; done; REPLY="$_r";; esac;;
	C10) _c89_unast_emit "$1"; REPLY="*${REPLY}";;
	C11) case $# in 0) REPLY="$_v";; 1) _c89_unast_emit "$1";; *) _r=; for _ch in "$@"; do _c89_unast_emit "$_ch"; _r="$_r$REPLY"; done; REPLY="$_r";; esac;;
	C12) _c89_unast_emit "$1"; REPLY="struct ${REPLY}";;
	C13) _c89_unast_emit "$1"; REPLY="union ${REPLY}";;
	C14) _c89_unast_emit "$1"; REPLY="enum ${REPLY}";;
	C15) _c89_unast_emit "$1"; _r="$REPLY"
		_c89_unast_emit "$2"; REPLY="${_r} ${REPLY}";;
	C16) case $# in 0) REPLY="$_v";; 1) _c89_unast_emit "$1";; *) _r=; for _ch in "$@"; do _c89_unast_emit "$_ch"; _r="$_r$REPLY"; done; REPLY="$_r";; esac;;
	C17) case $# in 0) REPLY="$_v";; 1) _c89_unast_emit "$1";; *) _r=; for _ch in "$@"; do _c89_unast_emit "$_ch"; _r="$_r$REPLY"; done; REPLY="$_r";; esac;;
	C18) case $# in 0) REPLY="$_v";; *) _c89_unast_emit "$1";; esac;;
	C19) _r=""
		for _ch in "$@"; do
			case "$_r" in "") ;; *) _r="$_r,";; esac
			_c89_unast_emit "$_ch"; _r="$_r$REPLY"
		done; REPLY="$_r";;
	C20) _c89_unast_emit "$1"; _r="$REPLY"
		shift 1
		_si=1
		case $# in 0) ;; *) _c89_unast_emit "$1"; _r="${_r} = $REPLY"; shift;; esac
		REPLY="${_r}";;
	C21) case $# in 0) REPLY="$_v";; 1) _c89_unast_emit "$1";; *) _r=; for _ch in "$@"; do _c89_unast_emit "$_ch"; _r="$_r$REPLY"; done; REPLY="$_r";; esac;;
	C22) _r="{"
		for _ch in "$@"; do
			case "$_r" in "{") ;; *) _r="$_r,";; esac
			_c89_unast_emit "$_ch"; _r="$_r$REPLY"
		done; REPLY="$_r,}";;
	C23) case $# in 0) REPLY="return ;";; *) _c89_unast_emit "$1"; REPLY="return ${REPLY};";; esac;;
	C24) REPLY="break;";;
	C25) REPLY="continue;";;
	C26) _c89_unast_emit "$1"; REPLY="goto ${REPLY};";;
	C27) _c89_unast_emit "$1"; _r="if($REPLY"
		_c89_unast_emit "$2"; _r="${_r})$REPLY"
		shift 2
		_si=2
		case $# in 0) ;; *) _c89_unast_emit "$1"; _r="${_r} else $REPLY"; shift;; esac
		REPLY="${_r}";;
	C28) _c89_unast_emit "$1"; _r="while($REPLY"
		_c89_unast_emit "$2"; REPLY="${_r})${REPLY}";;
	C29) _r="for("
		case $# in 0) ;; *) _c89_unast_emit "$1"; _r="${_r}$REPLY"; shift;; esac
		_si=1
		case $# in 0) ;; *) _c89_unast_emit "$1"; _r="${_r};$REPLY"; shift;; esac
		case $# in 0) ;; *) _c89_unast_emit "$1"; _r="${_r};$REPLY"; shift;; esac
		case $# in 0) ;; *) _c89_unast_emit "$1"; _r="${_r})$REPLY"; shift;; esac
		case $# in 0) ;; *) _c89_unast_emit "$1"; _r="${_r} $REPLY"; shift;; esac
		REPLY="${_r}";;
	C30) _c89_unast_emit "$1"; _r="do $REPLY"
		_c89_unast_emit "$2"; REPLY="${_r} while(${REPLY});";;
	C31) _c89_unast_emit "$1"; _r="switch($REPLY"
		_c89_unast_emit "$2"; REPLY="${_r})${REPLY}";;
	C32) _c89_unast_emit "$1"; _r="case $REPLY"
		_c89_unast_emit "$2"; REPLY="${_r}: ${REPLY}";;
	C33) _c89_unast_emit "$1"; REPLY="default:${REPLY}";;
	C34) _c89_unast_emit "$1"; REPLY="sizeof(${REPLY});";;
	C35) _c89_unast_emit "$1"; REPLY="#${REPLY}";;
	C36) _c89_unast_emit "$1"; REPLY="{${REPLY}";;
	C37) case $# in 0) case "$_v" in ?*) REPLY="$_v";; *) REPLY="}";; esac;; 1) _c89_unast_emit "$1";; *) _r=; for _ch in "$@"; do _c89_unast_emit "$_ch"; _r="$_r$REPLY"; done; REPLY="$_r";; esac;;
	C38) _c89_unast_emit "$1"; REPLY="${REPLY};";;
	C39) case $# in 0) REPLY="$_v";; *) _c89_unast_emit "$1";; esac;;
	C40) case $# in 0) REPLY="$_v";; 1) _c89_unast_emit "$1";; *) _r=; for _ch in "$@"; do _c89_unast_emit "$_ch"; _r="$_r$REPLY"; done; REPLY="$_r";; esac;;
	C41) _c89_unast_emit "$1"; REPLY="sizeof(${REPLY})";;
	C42) _r=""
		for _ch in "$@"; do
			case "$_r" in "") ;; *) _r="$_r ";; esac
			_c89_unast_emit "$_ch"; _r="$_r$REPLY"
		done; REPLY="$_r";;
	C43) _c89_unast_emit "$1"; REPLY="(${REPLY})";;
	C44) _r=""
		for _ch in "$@"; do
			case "$_r" in "") ;; *) _r="$_r,";; esac
			_c89_unast_emit "$_ch"; _r="$_r$REPLY"
		done; REPLY="$_r";;
	C45) REPLY="\"$_v\"";;
	C46) REPLY="'$_v'";;
	C47) REPLY="$_v";;
	C48) REPLY="$_v";;
	C49) _c89_unast_emit "$1"; REPLY="-${REPLY}";;
	C50) _c89_unast_emit "$1"; REPLY="!${REPLY}";;
	C51) _c89_unast_emit "$1"; REPLY="~${REPLY}";;
	C52) _c89_unast_emit "$1"; REPLY="*${REPLY}";;
	C53) _c89_unast_emit "$1"; REPLY="&${REPLY}";;
	C54) _c89_unast_emit "$1"; REPLY="++${REPLY}";;
	C55) _c89_unast_emit "$1"; _r="$REPLY"
		_c89_unast_emit "$2"; REPLY="$_r$_v$REPLY";;
	C56) _c89_unast_emit "$1"; _r="$REPLY("; shift
		local _sep=
		for _ch in "$@"; do
			case "$_sep" in ?*) _r="$_r, ";; esac
			_c89_unast_emit "$_ch"; _r="$_r$REPLY"; _sep=1
		done; REPLY="$_r)";;
	C58) _c89_unast_emit "$1"; _r="$REPLY["; shift
		local _sep=
		for _ch in "$@"; do
			case "$_sep" in ?*) _r="$_r, ";; esac
			_c89_unast_emit "$_ch"; _r="$_r$REPLY"; _sep=1
		done; REPLY="$_r]";;
	C60) _c89_unast_emit "$1"; _r="$REPLY."
		_c89_unast_emit "$2"; REPLY="$_r$REPLY";;
	C61) _c89_unast_emit "$1"; _r="$REPLY->"
		_c89_unast_emit "$2"; REPLY="$_r$REPLY";;
	C62) _c89_unast_emit "$1"; REPLY="$REPLY++";;
	C63) _c89_unast_emit "$1"; REPLY="$REPLY--";;
	C64) _c89_unast_emit "$1"; _r="$REPLY?"
		_c89_unast_emit "$2"; _r="$_r$REPLY:"
		_c89_unast_emit "$3"; REPLY="$_r$REPLY";;
	*) REPLY="??${_t}??";;
	esac
}

_c89_unast_emit_root () { _c89_unast_emit "$@"; }

c89_unast () {
	_readall; eval "$REPLY"
	_c89_unast_emit_root 0
	_printr1 "$REPLY"
}

# --- modules/tool/c89cc.sh ---
# ============================================================
# Компилятор C89: AST → бинарный файл x86-64 ELF64
# ============================================================
# Использование: printf '%s' 'int main(){return 42;}' | sh gen/c89.sh | sh gen/c89cc.sh > a.out
# chmod +x a.out && ./a.out; echo $?
#
# Читает AST (присваивания переменных V*/X*) из stdin.
# Выводит исполняемый файл Linux x86-64 ELF64 в stdout.


# ============================================================
# Чисто-оболочное преобразование чисел/символов (без printf, без PATH)
# ============================================================

# Десятичное (0-255) → 2-символьный шестнадцатеричный в верхнем регистре. Результат в REPLY.
_tool_c89cc_d2h () {
	case "$1" in '') REPLY="00"; return;; esac
	local _hi=$(($1 / 16)) _lo=$(($1 % 16)) _hc _lc
	case $_hi in 0) _hc=0;; 1) _hc=1;; 2) _hc=2;; 3) _hc=3;;
	4) _hc=4;; 5) _hc=5;; 6) _hc=6;; 7) _hc=7;; 8) _hc=8;;
	9) _hc=9;; 10) _hc=A;; 11) _hc=B;; 12) _hc=C;;
	13) _hc=D;; 14) _hc=E;; 15) _hc=F;; esac
	case $_lo in 0) _lc=0;; 1) _lc=1;; 2) _lc=2;; 3) _lc=3;;
	4) _lc=4;; 5) _lc=5;; 6) _lc=6;; 7) _lc=7;; 8) _lc=8;;
	9) _lc=9;; 10) _lc=A;; 11) _lc=B;; 12) _lc=C;;
	13) _lc=D;; 14) _lc=E;; 15) _lc=F;; esac
	REPLY="$_hc$_lc"
}

# сохраняем старший байт UTF-8 между вызовами
_UTF8_HIGH_BYTE=

# Символ → десятичное значение ASCII. Результат в REPLY.
_tool_c89cc_c2d () {
    local _byte="$1"
    local _code
    
    # Получаем числовой код байта
    _code=$(printf '%d' "'$_byte" 2>/dev/null)

    #========================================================

    # Если есть сохраненный старший байт - собираем русскую букву
    if test -n "$_UTF8_HIGH_BYTE"; then
        echo "DEBUG: Processing with stored high byte: $_UTF8_HIGH_BYTE, low byte: $_code" >&2
        if test "$_UTF8_HIGH_BYTE" -eq 208; then
            # D0 xx -> А-п (1040-1071) в Unicode, но нам нужен второй байт как есть
            REPLY=$_code
            echo "DEBUG: ВТОРОЙ БАЙТ ПОЛУЧЕН Russian char (D0) second byte: $_code" >&2

        else
            # D1 xx -> р-я (1072-1103) + Ё/ё
            case $_code in
            144) REPLY=168; echo "DEBUG: Ё" >&2;;
            176) REPLY=184; echo "DEBUG: ё" >&2;;
            *) REPLY=$_code; echo "DEBUG: Russian char (D1) second byte: $_code" >&2;;
            esac
        fi
        # Очищаем переменную после использования
        _UTF8_HIGH_BYTE=
        echo "DEBUG: Cleared _UTF8_HIGH_BYTE" >&2
        return
    fi
    
    # Старший байт UTF-8 (D0 или D1)
    if test "$_code" -eq 208 || test "$_code" -eq 209; then
        _UTF8_HIGH_BYTE=$_code
        echo "DEBUG: Stored high byte: $_UTF8_HIGH_BYTE, returning empty" >&2
        REPLY=
        return
    fi
    
    # ASCII символы (0-127)
    case "$_byte" in
    ' ') REPLY=32;;
    '!') REPLY=33;;
    '"') REPLY=34;;
    '#') REPLY=35;;
    '$') REPLY=36;;
    '%') REPLY=37;;
    '&') REPLY=38;;
    "'") REPLY=39;;
    '(') REPLY=40;;
    ')') REPLY=41;;
    '*') REPLY=42;;
    '+') REPLY=43;;
    ',') REPLY=44;;
    '-') REPLY=45;;
    '.') REPLY=46;;
    '/') REPLY=47;;
    '0') REPLY=48;;
    '1') REPLY=49;;
    '2') REPLY=50;;
    '3') REPLY=51;;
    '4') REPLY=52;;
    '5') REPLY=53;;
    '6') REPLY=54;;
    '7') REPLY=55;;
    '8') REPLY=56;;
    '9') REPLY=57;;
    ':') REPLY=58;;
    ';') REPLY=59;;
    '<') REPLY=60;;
    '=') REPLY=61;;
    '>') REPLY=62;;
    '?') REPLY=63;;
    '@') REPLY=64;;
    'A') REPLY=65;;
    'B') REPLY=66;;
    'C') REPLY=67;;
    'D') REPLY=68;;
    'E') REPLY=69;;
    'F') REPLY=70;;
    'G') REPLY=71;;
    'H') REPLY=72;;
    'I') REPLY=73;;
    'J') REPLY=74;;
    'K') REPLY=75;;
    'L') REPLY=76;;
    'M') REPLY=77;;
    'N') REPLY=78;;
    'O') REPLY=79;;
    'P') REPLY=80;;
    'Q') REPLY=81;;
    'R') REPLY=82;;
    'S') REPLY=83;;
    'T') REPLY=84;;
    'U') REPLY=85;;
    'V') REPLY=86;;
    'W') REPLY=87;;
    'X') REPLY=88;;
    'Y') REPLY=89;;
    'Z') REPLY=90;;
    '[') REPLY=91;;
    '\') REPLY=92;;
    ']') REPLY=93;;
    '^') REPLY=94;;
    '_') REPLY=95;;
    '`') REPLY=96;;
    'a') REPLY=97;;
    'b') REPLY=98;;
    'c') REPLY=99;;
    'd') REPLY=100;;
    'e') REPLY=101;;
    'f') REPLY=102;;
    'g') REPLY=103;;
    'h') REPLY=104;;
    'i') REPLY=105;;
    'j') REPLY=106;;
    'k') REPLY=107;;
    'l') REPLY=108;;
    'm') REPLY=109;;
    'n') REPLY=110;;
    'o') REPLY=111;;
    'p') REPLY=112;;
    'q') REPLY=113;;
    'r') REPLY=114;;
    's') REPLY=115;;
    't') REPLY=116;;
    'u') REPLY=117;;
    'v') REPLY=118;;
    'w') REPLY=119;;
    'x') REPLY=120;;
    'y') REPLY=121;;
    'z') REPLY=122;;
    '{') REPLY=123;;
    '|') REPLY=124;;
    '}') REPLY=125;;
    '~') REPLY=126;;
    *) REPLY=63;;
    esac
}

# НУЖНО ЗАМЕНИТЬ _tool_c89cc_c2d () на это:
_tool_c89cc_c2d_utf8 () {
    local _b1="$1" _b2="$2" _n1 _n2
    
    # Получаем числовой код первого байта
    case "$_b1" in
    ' ') _n1=32;; '!') _n1=33;; '"') _n1=34;; '#') _n1=35;;
    '$') _n1=36;; '%') _n1=37;; '&') _n1=38;; "'") _n1=39;;
    '(') _n1=40;; ')') _n1=41;; '*') _n1=42;; '+') _n1=43;;
    ',') _n1=44;; '-') _n1=45;; '.') _n1=46;; '/') _n1=47;;
    '0') _n1=48;; '1') _n1=49;; '2') _n1=50;; '3') _n1=51;;
    '4') _n1=52;; '5') _n1=53;; '6') _n1=54;; '7') _n1=55;;
    '8') _n1=56;; '9') _n1=57;; ':') _n1=58;; ';') _n1=59;;
    '<') _n1=60;; '=') _n1=61;; '>') _n1=62;; '?') _n1=63;;
    '@') _n1=64;;
    'A') _n1=65;; 'B') _n1=66;; 'C') _n1=67;; 'D') _n1=68;;
    'E') _n1=69;; 'F') _n1=70;; 'G') _n1=71;; 'H') _n1=72;;
    'I') _n1=73;; 'J') _n1=74;; 'K') _n1=75;; 'L') _n1=76;;
    'M') _n1=77;; 'N') _n1=78;; 'O') _n1=79;; 'P') _n1=80;;
    'Q') _n1=81;; 'R') _n1=82;; 'S') _n1=83;; 'T') _n1=84;;
    'U') _n1=85;; 'V') _n1=86;; 'W') _n1=87;; 'X') _n1=88;;
    'Y') _n1=89;; 'Z') _n1=90;; '[') _n1=91;; '\') _n1=92;;
    ']') _n1=93;; '^') _n1=94;; '_') _n1=95;; '`') _n1=96;;
    'a') _n1=97;; 'b') _n1=98;; 'c') _n1=99;; 'd') _n1=100;;
    'e') _n1=101;; 'f') _n1=102;; 'g') _n1=103;; 'h') _n1=104;;
    'i') _n1=105;; 'j') _n1=106;; 'k') _n1=107;; 'l') _n1=108;;
    'm') _n1=109;; 'n') _n1=110;; 'o') _n1=111;; 'p') _n1=112;;
    'q') _n1=113;; 'r') _n1=114;; 's') _n1=115;; 't') _n1=116;;
    'u') _n1=117;; 'v') _n1=118;; 'w') _n1=119;; 'x') _n1=120;;
    'y') _n1=121;; 'z') _n1=122;; '{') _n1=123;; '|') _n1=124;;
    '}') _n1=125;; '~') _n1=126;;
    'А') _n1=192;; 'Б') _n1=193;; 'В') _n1=194;; 'Г') _n1=195;;
    'Д') _n1=196;; 'Е') _n1=197;; 'Ё') _n1=168;; 'Ж') _n1=198;;
    'З') _n1=199;; 'И') _n1=200;; 'Й') _n1=201;; 'К') _n1=202;;
    'Л') _n1=203;; 'М') _n1=204;; 'Н') _n1=205;; 'О') _n1=206;;
    'П') _n1=207;; 'Р') _n1=208;; 'С') _n1=209;; 'Т') _n1=210;;
    'У') _n1=211;; 'Ф') _n1=212;; 'Х') _n1=213;; 'Ц') _n1=214;;
    'Ч') _n1=215;; 'Ш') _n1=216;; 'Щ') _n1=217;; 'Ъ') _n1=218;;
    'Ы') _n1=219;; 'Ь') _n1=220;; 'Э') _n1=221;; 'Ю') _n1=222;;
    'Я') _n1=223;;
    'а') _n1=224;; 'б') _n1=225;; 'в') _n1=226;; 'г') _n1=227;;
    'д') _n1=228;; 'е') _n1=229;; 'ё') _n1=184;; 'ж') _n1=230;;
    'з') _n1=231;; 'и') _n1=232;; 'й') _n1=233;; 'к') _n1=234;;
    'л') _n1=235;; 'м') _n1=236;; 'н') _n1=237;; 'о') _n1=238;;
    'п') _n1=239;; 'р') _n1=240;; 'с') _n1=241;; 'т') _n1=242;;
    'у') _n1=243;; 'ф') _n1=244;; 'х') _n1=245;; 'ц') _n1=246;;
    'ч') _n1=247;; 'ш') _n1=248;; 'щ') _n1=249;; 'ъ') _n1=250;;
    'ы') _n1=251;; 'ь') _n1=252;; 'э') _n1=253;; 'ю') _n1=254;;
    'я') _n1=255;;
    *) _n1=63;;
    esac
    
    # Если первый байт D0 (208) или D1 (209) и есть второй байт
    if test $# -eq 2 && { test $_n1 -eq 208 || test $_n1 -eq 209; }; then
        # Получаем код второго байта
        case "$_b2" in
        ' ') _n2=32;; '!') _n2=33;; '"') _n2=34;; '#') _n2=35;;
        '$') _n2=36;; '%') _n2=37;; '&') _n2=38;; "'") _n2=39;;
        '(') _n2=40;; ')') _n2=41;; '*') _n2=42;; '+') _n2=43;;
        ',') _n2=44;; '-') _n2=45;; '.') _n2=46;; '/') _n2=47;;
        '0') _n2=48;; '1') _n2=49;; '2') _n2=50;; '3') _n2=51;;
        '4') _n2=52;; '5') _n2=53;; '6') _n2=54;; '7') _n2=55;;
        '8') _n2=56;; '9') _n2=57;; ':') _n2=58;; ';') _n2=59;;
        '<') _n2=60;; '=') _n2=61;; '>') _n2=62;; '?') _n2=63;;
        '@') _n2=64;;
        'A') _n2=65;; 'B') _n2=66;; 'C') _n2=67;; 'D') _n2=68;;
        'E') _n2=69;; 'F') _n2=70;; 'G') _n2=71;; 'H') _n2=72;;
        'I') _n2=73;; 'J') _n2=74;; 'K') _n2=75;; 'L') _n2=76;;
        'M') _n2=77;; 'N') _n2=78;; 'O') _n2=79;; 'P') _n2=80;;
        'Q') _n2=81;; 'R') _n2=82;; 'S') _n2=83;; 'T') _n2=84;;
        'U') _n2=85;; 'V') _n2=86;; 'W') _n2=87;; 'X') _n2=88;;
        'Y') _n2=89;; 'Z') _n2=90;; '[') _n2=91;; '\') _n2=92;;
        ']') _n2=93;; '^') _n2=94;; '_') _n2=95;; '`') _n2=96;;
        'a') _n2=97;; 'b') _n2=98;; 'c') _n2=99;; 'd') _n2=100;;
        'e') _n2=101;; 'f') _n2=102;; 'g') _n2=103;; 'h') _n2=104;;
        'i') _n2=105;; 'j') _n2=106;; 'k') _n2=107;; 'l') _n2=108;;
        'm') _n2=109;; 'n') _n2=110;; 'o') _n2=111;; 'p') _n2=112;;
        'q') _n2=113;; 'r') _n2=114;; 's') _n2=115;; 't') _n2=116;;
        'u') _n2=117;; 'v') _n2=118;; 'w') _n2=119;; 'x') _n2=120;;
        'y') _n2=121;; 'z') _n2=122;; '{') _n2=123;; '|') _n2=124;;
        '}') _n2=125;; '~') _n2=126;;
        *) _n2=63;;
        esac
        
        # D0 xx -> 192-223 (А-Я, а-п)
        if test $_n1 -eq 208; then
            REPLY=$((_n2 - 32))
        # D1 xx -> 168 (Ё), 184 (ё), 224-255 (р-я)
        else
            REPLY=$((_n2 + 48))
        fi
    else
        REPLY=$_n1
    fi
}



# Десятичное → сырой байт в stdout (использует самый быстрый доступный примитив вывода)
if command -v printf >/dev/null 2>&1; then
	_out_byte () { printf "\\$(($1/64))$((($1/8)%8))$(($1%8))"; }
elif command -v print >/dev/null 2>&1; then
	_out_byte () { print -n "\\0$(($1/64))$((($1/8)%8))$(($1%8))"; }
else
	_out_byte () { command -p printf "\\$(($1/64))$((($1/8)%8))$(($1%8))"; }
fi

# Выдать один шестнадцатеричный байт из десятичного значения
_tool_c89cc_emit_d () { _tool_c89cc_d2h "$1"; _tool_c89cc_emit "$REPLY"; }

# Выдать смещение стека от rbp. Использует 1-байтовый disp8 для off<=127, иначе 4-байтовый disp32.
# Вызывающий должен использовать правильный код операции: 45/85 для mov, 45/85 для lea (байт ModRM отличается).
# Эта функция вызывается ПОСЛЕ выдачи байта кода операции+ModRM.
_tool_c89cc_emit_off () {
	if test $1 -le 127; then
		_tool_c89cc_d2h $(( 256 - $1 ))
		_tool_c89cc_emit "$REPLY"
	else
		_tool_c89cc_emit_le32 $(( 0 - $1 ))
	fi
}

# Выдать mov rax, [rbp-off]
_tool_c89cc_load_local () {
	if test $1 -le 127; then _tool_c89cc_emit "48 8B 45"
	else _tool_c89cc_emit "48 8B 85"; fi
	_tool_c89cc_emit_off $1
}
# Выдать mov [rbp-off], rax
_tool_c89cc_store_local () {
	if test $1 -le 127; then _tool_c89cc_emit "48 89 45"
	else _tool_c89cc_emit "48 89 85"; fi
	_tool_c89cc_emit_off $1
}
# Выдать lea rax, [rbp-off]
_tool_c89cc_lea_local () {
	if test $1 -le 127; then _tool_c89cc_emit "48 8D 45"
	else _tool_c89cc_emit "48 8D 85"; fi
	_tool_c89cc_emit_off $1
}

# ============================================================
# Буфер кода
# ============================================================
# Код хранится в виде переменных для каждого байта: _CB_0, _CB_1, ...
# Каждая содержит 2-символьную шестнадцатеричную строку (например, "E8", "FF").
# _IP отслеживает текущее смещение (в байтах).
_IP=0

# Добавить шестнадцатеричные байты в буфер кода. Аргументы: шестнадцатеричные пары (например, "48 89 E5")
_tool_c89cc_emit () {
	for _b in $1; do
		eval "_CB_$_IP=\$_b"
		_IP=$((_IP + 1))
	done
}

# Прочитать байт из буфера кода по смещению $1. Результат в REPLY.
_tool_c89cc_byte () { eval "REPLY=\$_CB_$1"; }

# Выдать 32-битное непосредственное значение в формате little-endian
_tool_c89cc_emit_le32 () {
	local _v=$1
	_tool_c89cc_emit_d $(( _v & 255 ))
	_tool_c89cc_emit_d $(( (_v >> 8) & 255 ))
	_tool_c89cc_emit_d $(( (_v >> 16) & 255 ))
	_tool_c89cc_emit_d $(( (_v >> 24) & 255 ))
}

# Выдать 64-битное значение в формате little-endian
_tool_c89cc_emit_le64 () {
	_tool_c89cc_emit_le32 "$1"
	_tool_c89cc_emit_le32 0
}

# ============================================================
# Метки и перемещения
# ============================================================
_LABELS=       # space-separated "name=offset" pairs
_RELOCS=       # space-separated "offset=name" pairs (rel32 fixups)
_JMP_N=0       # jump label counter
_BRK_LBL=      # current break target label (loop/switch exit)
_CONT_LBL=     # current continue target label (loop top)
_SW_OFF=        # current switch value stack offset (for case comparisons)

_tool_c89cc_label () {
	_LABELS="$_LABELS $1=$_IP"
}

# Выдать заполнитель rel32 и записать перемещение
_tool_c89cc_reloc_rel32 () {
	_RELOCS="$_RELOCS ${_IP}=$1"
	_tool_c89cc_emit "00 00 00 00"    # placeholder
}

# Выделить имя метки перехода. Возвращает имя в REPLY.
_tool_c89cc_jmp_label () {
	_JMP_N=$((_JMP_N + 1))
	REPLY=".LJ$_JMP_N"
}

# Выдать условный переход (6 байт: 0F 8x rel32) с автоматической меткой.
# $1 = код условия (84=je, 85=jne, 8C=jl, 8F=jg, 8E=jle, 8D=jge)
# Возвращает: имя метки в REPLY (будет определено позже в цели)
_tool_c89cc_emit_jcc () {
	_tool_c89cc_jmp_label
	local _jlbl=$REPLY
	_tool_c89cc_emit "0F $1"
	_RELOCS="$_RELOCS J${_IP}=$_jlbl"
	_tool_c89cc_emit "00 00 00 00"
	REPLY=$_jlbl
}

# Выдать безусловный переход (5 байт: E9 rel32) с автоматической меткой.
_tool_c89cc_emit_jmp () {
	_tool_c89cc_jmp_label
	local _jlbl=$REPLY
	_tool_c89cc_emit "E9"
	_RELOCS="$_RELOCS J${_IP}=$_jlbl"
	_tool_c89cc_emit "00 00 00 00"
	REPLY=$_jlbl
}

# Определить метку перехода в текущей позиции
_tool_c89cc_jmp_target () {
	_tool_c89cc_label "$1"
}

# Разрешить все перемещения после генерации кода
_tool_c89cc_fixup () {
	# Вычислить адреса секции данных для исправлений строк/глобальных переменных
	local _str_base_addr=$(( _BASE_ADDR + _HDR_SIZE + _IP ))
	local _str_size=$(( ${#_STR_DATA} / 2 ))
	local _glob_base_addr=$(( _str_base_addr + _str_size ))

	for _rel in $_RELOCS; do
		local _src="${_rel%%=*}" _tgt_name="${_rel#*=}"

		# Перемещение адреса строки: S<смещение>=STR<id>
		case "$_src" in S*)
			local _soff=${_src#S}
			local _str_id=${_tgt_name#STR}
			eval "local _sdataoff=\$_STR_OFF_$_str_id"
			# sdataoff — это смещение в шестнадцатеричных символах, преобразовать в байтовое смещение
			local _sbyte=$(( _sdataoff / 2 ))
			local _addr=$(( _str_base_addr + _sbyte ))
			_tool_c89cc_patch_le64 $_soff $_addr
			continue;; esac

		# Перемещение адреса глобальной переменной: G<смещение>=GLOB<смещение_в_данных>
		case "$_src" in G*)
			local _goff=${_src#G}
			local _gdataoff=${_tgt_name#GLOB}
			local _addr=$(( _glob_base_addr + _gdataoff ))
			_tool_c89cc_patch_le64 $_goff $_addr
			continue;; esac

		# Перемещение перехода: J<смещение>=<метка>
		case "$_src" in J*)
			local _jsrc=${_src#J}
			local _jtgt_off=
			for _lbl in $_LABELS; do
				case "$_lbl" in "${_tgt_name}="*)
					_jtgt_off="${_lbl#*=}"; break;; esac
			done
			case "$_jtgt_off" in ?*)
				local _jdisp=$(( _jtgt_off - (_jsrc + 4) ))
				_tool_c89cc_patch_le32 $_jsrc $_jdisp;; esac
			continue;; esac

		# Обычное перемещение rel32 (вызов)
		local _tgt_off=
		for _lbl in $_LABELS; do
			case "$_lbl" in "${_tgt_name}="*)
				_tgt_off="${_lbl#*=}"; break;; esac
		done
		case "$_tgt_off" in '') continue;; esac
		local _disp=$(( _tgt_off - (_src + 4) ))
		_tool_c89cc_patch_le32 $_src $_disp
	done
}

# Заплатка 8 байт (64-битный адрес) по смещению в буфере кода
_tool_c89cc_patch_le64 () {
	local _off=$1 _v=$2 _i=0
	while test $_i -lt 8; do
		_tool_c89cc_d2h $(( _v % 256 ))
		eval "_CB_$((_off + _i))=\$REPLY"
		_v=$(( _v / 256 ))
		_i=$((_i + 1))
	done
}

# Заплатка 4 байта по смещению в буфере кода
_tool_c89cc_patch_le32 () {
	local _off=$1 _v=$2
	_tool_c89cc_d2h $(( _v & 255 )); eval "_CB_$_off=\$REPLY"
	_tool_c89cc_d2h $(( (_v >> 8) & 255 )); eval "_CB_$((_off+1))=\$REPLY"
	_tool_c89cc_d2h $(( (_v >> 16) & 255 )); eval "_CB_$((_off+2))=\$REPLY"
	_tool_c89cc_d2h $(( (_v >> 24) & 255 )); eval "_CB_$((_off+3))=\$REPLY"
}

# ============================================================
# Таблица символов
# ============================================================
_SYM_N=0       # number of symbols
_SCOPE=0       # current scope depth
_FRAME_SIZE=0  # current function's stack frame size

# Добавить символ: имя, тип, смещение, elem_size (для масштаба индекса указателя)
_tool_c89cc_sym_add () {
	_SYM_N=$((_SYM_N + 1))
	eval "_SYM_NAME_$_SYM_N=\"\$1\""
	eval "_SYM_KIND_$_SYM_N=\"\$2\""     # func, local, global, param
	eval "_SYM_SCOPE_$_SYM_N=$_SCOPE"
	eval "_SYM_OFF_$_SYM_N=\$3"          # stack offset or 0
	eval "_SYM_ESIZE_$_SYM_N=\${4:-8}"  # element size for subscript (default 8)
}

# Поиск символа по имени (поиск в текущей области видимости и выше)
# Возвращает: "тип смещение esize"
_tool_c89cc_sym_find () {
	local _i=$_SYM_N _n
	while test $_i -gt 0; do
		eval "_n=\"\$_SYM_NAME_$_i\""
		case "$_n" in "$1")
			eval "REPLY=\"\$_SYM_KIND_$_i \$_SYM_OFF_$_i \$_SYM_ESIZE_$_i\""
			return 0;; esac
		_i=$((_i - 1))
	done
	REPLY=
	return 1
}

# Выделить локальную переменную в стеке. Возвращает смещение.
_tool_c89cc_alloc_local () {
	_FRAME_SIZE=$((_FRAME_SIZE + 8))
	REPLY=$_FRAME_SIZE
}

# Определить размер элемента для узла выражения указателя.
# Обходит AST, чтобы найти базовую переменную, и возвращает ее esize в REPLY.
# Используется обработчиком разыменования * для выбора между загрузкой байта или qword.
_tool_c89cc_resolve_esize () {
	local _re_n=$1 _re_t
	_tool_c89cc_type "$_re_n"; _re_t=$REPLY
	case "$_re_t" in
	C39) # expr — delegate to child
		_tool_c89cc_children "$_re_n"
		_tool_c89cc_resolve_esize "$REPLY";;
	C48) # ident — look up symbol esize
		_tool_c89cc_val "$_re_n"
		case "$REPLY" in [a-zA-Z_]*)
			if _tool_c89cc_sym_find "$REPLY"; then
				local _re_rest="$REPLY"
				_re_rest="${_re_rest#* }"; _re_rest="${_re_rest#* }"
				REPLY="${_re_rest%% *}"; return
			fi;; esac
		REPLY=8;;
	C53) # unary & — esize of the operand variable
		_tool_c89cc_children "$_re_n"
		_tool_c89cc_resolve_esize "$REPLY";;
	C55) # binary op (e.g., ptr + n) — esize of LHS
		_tool_c89cc_children "$_re_n"
		_tool_c89cc_resolve_esize "${REPLY%% *}";;
	C43) # paren_expr — delegate to child
		_tool_c89cc_children "$_re_n"
		_tool_c89cc_resolve_esize "$REPLY";;
	C58) # subscript a[i] — esize of base variable's element type
		_tool_c89cc_children "$_re_n"
		_tool_c89cc_resolve_esize "${REPLY%% *}";;
	*) REPLY=8;;
	esac
}

# ============================================================
# Глобальные переменные
# ============================================================
_GLOB_N=0        # number of globals
_GLOB_DATA=      # hex bytes for .data section

_tool_c89cc_glob_add () {
	_GLOB_N=$((_GLOB_N + 1))
	eval "_GLOB_NAME_$_GLOB_N=\"\$1\""
	eval "_GLOB_SIZE_$_GLOB_N=\$2"
	# Выделить в секции данных (смещение от начала данных)
	local _doff=0 _i=1
	while test $_i -lt $_GLOB_N; do
		eval "_doff=\$((_doff + \$_GLOB_SIZE_$_i))"
		_i=$((_i + 1))
	done
	eval "_GLOB_OFF_$_GLOB_N=$_doff"
	_tool_c89cc_sym_add "$1" "global" "$_doff" "${3:-8}"
	# Заполнить нулями в секции данных
	local _j=0
	while test $_j -lt $2; do _GLOB_DATA="${_GLOB_DATA}00"; _j=$((_j + 1)); done
}

# Поиск глобальной переменной по имени → смещение в секции данных
_tool_c89cc_glob_find () {
	local _i=1
	while test $_i -le $_GLOB_N; do
		eval "case \"\$_GLOB_NAME_$_i\" in \"\$1\") eval \"REPLY=\\\$_GLOB_OFF_$_i\"; return 0;; esac"
		_i=$((_i + 1))
	done
	return 1
}

# ============================================================
# Реестр типов структур
# ============================================================
_STRUCT_N=0

# Зарегистрировать структуру: имя, количество полей, имена полей, размеры полей
_tool_c89cc_struct_def () {
	_STRUCT_N=$((_STRUCT_N + 1))
	eval "_STRUCT_NAME_$_STRUCT_N=\"\$1\""
	eval "_STRUCT_NFIELDS_$_STRUCT_N=0"
}

# Добавить поле в последнюю определенную структуру
_tool_c89cc_struct_field () {
	local _si=$_STRUCT_N _nf
	eval "_nf=\$_STRUCT_NFIELDS_$_si"
	_nf=$((_nf + 1))
	eval "_STRUCT_NFIELDS_$_si=$_nf"
	eval "_STRUCT_FNAME_${_si}_${_nf}=\"\$1\""
	eval "_STRUCT_FSIZE_${_si}_${_nf}=\$2"
}

# Поиск смещения поля структуры по имени структуры + имени поля
_tool_c89cc_struct_field_off () {
	local _sname=$1 _fname=$2 _i=1
	while test $_i -le $_STRUCT_N; do
		eval "local _sn=\"\$_STRUCT_NAME_$_i\""
		case "$_sn" in "$_sname")
			local _j=1 _off=0 _nf
			eval "_nf=\$_STRUCT_NFIELDS_$_i"
			while test $_j -le $_nf; do
				eval "local _fn=\"\$_STRUCT_FNAME_${_i}_${_j}\""
				case "$_fn" in "$_fname") REPLY=$_off; return 0;; esac
				eval "local _fs=\$_STRUCT_FSIZE_${_i}_${_j}"
				# Выровнять по 8 байт
				_off=$(( (_off + _fs + 7) & -8 ))
				_j=$((_j + 1))
			done
			REPLY=$_off; return 1;;  # field not found
		esac
		_i=$((_i + 1))
	done
	return 1
}

# ============================================================
# Строковые литералы
# ============================================================
_STR_N=0
_STR_DATA=

_tool_c89cc_add_string () {
    _STR_N=$((_STR_N + 1))
    eval "_STR_OFF_$_STR_N=${#_STR_DATA}"
    # Преобразовать строку в шестнадцатеричные байты, добавить нулевой терминатор
    local _s="$1" _c _saved_high_byte
    
    while test ${#_s} -gt 0; do
        _c="${_s%"${_s#?}"}"; _s="${_s#?}"
        
        # Сохраняем старший байт перед вызовом
        _saved_high_byte="$_UTF8_HIGH_BYTE"
        
        # Отладка: если есть сохраненный старший байт
        if test -n "$_saved_high_byte"; then
            echo "DEBUG: Processing with saved high byte: $_saved_high_byte" >&2
        fi
        
        case "$_c" in
        '\') # escape sequence
            _c="${_s%"${_s#?}"}"; _s="${_s#?}"
            case "$_c" in
            n) _STR_DATA="${_STR_DATA}0A";;
            t) _STR_DATA="${_STR_DATA}09";;
            r) _STR_DATA="${_STR_DATA}0D";;
            0) _STR_DATA="${_STR_DATA}00";;
            '\') _STR_DATA="${_STR_DATA}5C";;
            '"') _STR_DATA="${_STR_DATA}22";;
            *) 
                _tool_c89cc_c2d "$_c"
                if test -n "$REPLY"; then
                    # Если был сохранен старший байт
                    if test -n "$_saved_high_byte"; then
                        _tool_c89cc_d2h "$_saved_high_byte"
                        _byte1="$REPLY"
                        _tool_c89cc_d2h "$REPLY"
                        _byte2="$REPLY"
                        echo "DEBUG: UTF-8 pair: $_byte1 $_byte2 (high: $_saved_high_byte, low: $REPLY)" >&2
                        _STR_DATA="${_STR_DATA}$_byte1$_byte2"
                    else
                        _tool_c89cc_d2h "$REPLY"
                        #echo "DEBUG: ASCII byte: $REPLY" >&2
                        _STR_DATA="${_STR_DATA}$REPLY"
                    fi
                fi
            esac;;
        *) 
		    
            _tool_c89cc_c2d "$_c"
			_tmp=$REPLY #младший байт
            if test -n "$REPLY"; then
                # Если был сохранен старший байт
                if test -n "$_saved_high_byte"; then
				    echo " от _tool_c89cc_c2d получен младший байт $REPLY" >&2
					_tmp1=$REPLY
                    _tool_c89cc_d2h "$_saved_high_byte"
                    _byte1="$REPLY"
                    _tool_c89cc_d2h "$_tmp1"
                    _byte2="$REPLY"
                    echo "DEBUG: UTF-8 pair: $_byte1 $_byte2 (high: $_saved_high_byte, low: $_byte2)" >&2
                    _STR_DATA="${_STR_DATA}$_byte1$_byte2"
                else
                    _tool_c89cc_d2h "$REPLY"
                    #echo "DEBUG: ASCII byte: $REPLY" >&2
                    _STR_DATA="${_STR_DATA}$REPLY"
                fi
            fi
        esac
    done
    _STR_DATA="${_STR_DATA}00"  # null terminator
    echo "DEBUG: Final _STR_DATA: $_STR_DATA" >&2
    REPLY=$_STR_N
}

# ============================================================
# Обходчик AST
# ============================================================

# Получить код типа узла (первое слово X<n>)
_tool_c89cc_type () { eval "REPLY=\"\${X$1%% *}\""; }

# Получить значение узла
_tool_c89cc_val () { eval "REPLY=\"\${V$1:-}\""; }

# Получить дочерние узлы (все после кода типа)
_tool_c89cc_children () {
	eval "local _x=\"\$X$1\""
	REPLY="${_x#* }"
	case "$REPLY" in "$_x") REPLY=;; esac  # no children
}

# Основной рекурсивный обходчик AST
_tool_c89cc_node () {
	local _n=$1 _t _v
	_tool_c89cc_type "$_n"; _t=$REPLY
	_tool_c89cc_val "$_n"; _v=$REPLY

	case "$_t" in
	Ca) # Document root: process all children
		_tool_c89cc_children "$_n"; local _ca_chs="$REPLY"
		for _ch in $_ca_chs; do _tool_c89cc_node "$_ch"; done;;

	Cb) # file_body: process children
		_tool_c89cc_children "$_n"; local _cb_chs="$REPLY"
		for _ch in $_cb_chs; do _tool_c89cc_node "$_ch"; done;;

	Cd|Ce|Cf|Cg|Ch|Ci|Cj|Ck|Cl|Cm|Cn|Co|Cp|Cq|Cr|Cs) # type_item (int, char, void, ...)
		_tool_c89cc_children "$_n"; local _dt_chs="$REPLY"
		for _ch in $_dt_chs; do _tool_c89cc_decl "$_t" "$_ch"; done;;

	Ct|Cu) # struct/union item
		_tool_c89cc_children "$_n"
		for _ch in $REPLY; do _tool_c89cc_decl "$_t" "$_ch"; done;;

	C38) # expr_item: compile expression, discard result
		_tool_c89cc_children "$_n"; local _ei_chs="$REPLY"
		for _ch in $_ei_chs; do _tool_c89cc_expr "$_ch"; done;;

	C23) # return_item
		_tool_c89cc_children "$_n"
		case "$REPLY" in
		?*) _tool_c89cc_expr "$REPLY";;    # return expr → result in rax
		*) ;;                       # bare return
		esac
		# Эпилог: leave + ret
		_tool_c89cc_emit "C9"               # leave
		_tool_c89cc_emit "C3";;             # ret

	C24) # break_item — jump to break label
		case "$_BRK_LBL" in ?*)
			_tool_c89cc_emit "E9"
			_RELOCS="$_RELOCS J${_IP}=$_BRK_LBL"
			_tool_c89cc_emit "00 00 00 00";; esac;;
	C25) # continue_item — jump to continue label
		case "$_CONT_LBL" in ?*)
			_tool_c89cc_emit "E9"
			_RELOCS="$_RELOCS J${_IP}=$_CONT_LBL"
			_tool_c89cc_emit "00 00 00 00";; esac;;

	C27) # if_item: if(expr) item [else item]
		_tool_c89cc_children "$_n"; local _if_chs="$REPLY"
		set -- $_if_chs
		local _if_cond="$1" _if_then="$2" _if_else="${3:-}"
		_tool_c89cc_expr "$_if_cond"
		_tool_c89cc_emit "48 85 C0"          # test rax, rax
		_tool_c89cc_emit_jcc "84"; local _else_lbl=$REPLY  # je else/end
		_tool_c89cc_node "$_if_then"
		case "$_if_else" in ?*)
			_tool_c89cc_emit_jmp; local _end_lbl=$REPLY  # jmp end
			_tool_c89cc_jmp_target "$_else_lbl"
			_tool_c89cc_node "$_if_else"
			_tool_c89cc_jmp_target "$_end_lbl";;
		*)
			_tool_c89cc_jmp_target "$_else_lbl";;
		esac;;

	C28) # while_item: while(expr) item
		_tool_c89cc_children "$_n"; local _wh_chs="$REPLY"
		set -- $_wh_chs
		local _wh_cond="$1" _wh_body="$2"
		local _sav_brk=$_BRK_LBL _sav_cont=$_CONT_LBL
		_tool_c89cc_jmp_label; local _wh_top=$REPLY
		_tool_c89cc_jmp_target "$_wh_top"
		_tool_c89cc_expr "$_wh_cond"
		_tool_c89cc_emit "48 85 C0"
		_tool_c89cc_emit_jcc "84"; local _wh_exit=$REPLY
		_BRK_LBL=$_wh_exit; _CONT_LBL=$_wh_top
		_tool_c89cc_node "$_wh_body"
		# Переход обратно наверх
		_tool_c89cc_emit "E9"
		_RELOCS="$_RELOCS J${_IP}=$_wh_top"
		_tool_c89cc_emit "00 00 00 00"
		_tool_c89cc_jmp_target "$_wh_exit"
		_BRK_LBL=$_sav_brk; _CONT_LBL=$_sav_cont;;

	C29) # for_item: for(init;cond;incr) item
		_tool_c89cc_children "$_n"; local _for_chs="$REPLY"
		set -- $_for_chs
		local _for_body _for_init= _for_cond= _for_incr=
		case $# in
		1) _for_body=$1;;
		2) _for_cond=$1; _for_body=$2;;
		3) _for_init=$1; _for_cond=$2; _for_body=$3;;
		4) _for_init=$1; _for_cond=$2; _for_incr=$3; _for_body=$4;;
		esac
		local _sav_brk=$_BRK_LBL _sav_cont=$_CONT_LBL
		case "$_for_init" in ?*) _tool_c89cc_expr "$_for_init";; esac
		_tool_c89cc_jmp_label; local _for_top=$REPLY
		_tool_c89cc_jmp_target "$_for_top"
		local _for_exit_lbl=
		case "$_for_cond" in ?*)
			_tool_c89cc_expr "$_for_cond"
			_tool_c89cc_emit "48 85 C0"
			_tool_c89cc_emit_jcc "84"; _for_exit_lbl=$REPLY;;
		esac
		_tool_c89cc_jmp_label; local _for_cont=$REPLY
		_BRK_LBL=${_for_exit_lbl:-}; _CONT_LBL=$_for_cont
		_tool_c89cc_node "$_for_body"
		_tool_c89cc_jmp_target "$_for_cont"
		case "$_for_incr" in ?*) _tool_c89cc_expr "$_for_incr";; esac
		# Переход обратно наверх
		_tool_c89cc_emit "E9"
		_RELOCS="$_RELOCS J${_IP}=$_for_top"
		_tool_c89cc_emit "00 00 00 00"
		case "$_for_exit_lbl" in ?*) _tool_c89cc_jmp_target "$_for_exit_lbl";; esac
		_BRK_LBL=$_sav_brk; _CONT_LBL=$_sav_cont;;

	C30) # do_item: do item while(expr)
		_tool_c89cc_children "$_n"; local _do_chs="$REPLY"
		set -- $_do_chs
		local _do_body="$1" _do_cond="$2"
		local _sav_brk=$_BRK_LBL _sav_cont=$_CONT_LBL
		_tool_c89cc_jmp_label; local _do_top=$REPLY
		_tool_c89cc_jmp_label; local _do_exit=$REPLY
		_BRK_LBL=$_do_exit; _CONT_LBL=$_do_top
		_tool_c89cc_jmp_target "$_do_top"
		_tool_c89cc_node "$_do_body"
		_tool_c89cc_expr "$_do_cond"
		_tool_c89cc_emit "48 85 C0"
		_tool_c89cc_emit "0F 85"
		_RELOCS="$_RELOCS J${_IP}=$_do_top"
		_tool_c89cc_emit "00 00 00 00"
		_tool_c89cc_jmp_target "$_do_exit"
		_BRK_LBL=$_sav_brk; _CONT_LBL=$_sav_cont;;

	C31) # switch_item: switch(expr) { cases }
		_tool_c89cc_children "$_n"; local _sw_chs="$REPLY"
		set -- $_sw_chs
		local _sw_cond="$1" _sw_body="$2"
		local _sav_brk=$_BRK_LBL _sav_sw=$_SW_OFF
		# Скомпилировать условие, сохранить результат как локальную переменную
		_tool_c89cc_expr "$_sw_cond"
		_tool_c89cc_alloc_local; local _sw_loc=$REPLY
		_SW_OFF=$_sw_loc
		_tool_c89cc_store_local $_sw_loc  # mov [rbp-off], rax
		# Настроить метку break
		_tool_c89cc_jmp_label; local _sw_end=$REPLY
		_BRK_LBL=$_sw_end
		# Обработать тело switch (метки case/default обрабатываются ниже)
		_tool_c89cc_node "$_sw_body"
		_tool_c89cc_jmp_target "$_sw_end"
		_BRK_LBL=$_sav_brk; _SW_OFF=$_sav_sw;;

	C32) # case_item: case <value>: <statements>
		_tool_c89cc_children "$_n"; local _cs_chs="$REPLY"
		set -- $_cs_chs
		local _cs_val="$1"; shift
		# Сравнить значение switch со значением case
		_tool_c89cc_load_local $_SW_OFF  # mov rax, [rbp-sw_off]
		_tool_c89cc_emit "50"                                 # push rax (save switch val)
		_tool_c89cc_expr "$_cs_val"                           # rax = case value
		_tool_c89cc_emit "48 89 C1"                           # mov rcx, rax
		_tool_c89cc_emit "58"                                 # pop rax (switch val)
		_tool_c89cc_emit "48 39 C8"                           # cmp rax, rcx
		_tool_c89cc_emit_jcc "85"; local _cs_skip=$REPLY      # jne → skip
		# Тело case: скомпилировать оставшиеся дочерние элементы
		for _ch in "$@"; do _tool_c89cc_node "$_ch"; done
		_tool_c89cc_jmp_target "$_cs_skip";;

	C33) # default_item: default: <statements>
		_tool_c89cc_children "$_n"; local _df_chs="$REPLY"
		for _ch in $_df_chs; do _tool_c89cc_node "$_ch"; done;;

	C36) # block_item: { block_body }
		_tool_c89cc_children "$_n"; local _bi_chs="$REPLY"
		for _ch in $_bi_chs; do _tool_c89cc_node "$_ch"; done;;

	C37) # block_body: process children
		_tool_c89cc_children "$_n"; local _bb_chs="$REPLY"
		for _ch in $_bb_chs; do _tool_c89cc_node "$_ch"; done;;

	*) ;; # Unknown node type — skip
	esac
}

# ============================================================
# Обработчик объявлений
# ============================================================
_tool_c89cc_decl () {
	local _type_code=$1 _child=$2 _t _v
	_tool_c89cc_type "$_child"; _t=$REPLY
	_tool_c89cc_val "$_child"; _v=$REPLY
	# Определить размер элемента из ключевого слова типа
	# char/char * → esize=1 (байтовый элемент); char ** → esize=8 (указательные элементы)
	# Третий аргумент ($3) переопределяет, когда передается из рекурсии Cx — пропустить пересчет
	local _decl_esize=8
	case "${3+set}" in set) _decl_esize=$3;; *)
		case "$_type_code" in Ce)
			_decl_esize=1
			case "$_t" in Cx)
				_tool_c89cc_children "$_child"
				_tool_c89cc_type "$REPLY"
				case "$REPLY" in Cx) _decl_esize=8;; esac
			;; esac
		;; esac
	;; esac

	case "$_t" in
	Cy) # ident_decl: name + after_name
		_tool_c89cc_children "$_child"
		local _name_node="${REPLY%% *}" _rest="${REPLY#* }"
		_tool_c89cc_val "$_name_node"; local _name=$REPLY

		# Проверить, что следует: func_def или переменная
		case "$_rest" in '')
			# Простое объявление (без инициализатора, без функции)
			case "$_SCOPE" in
			0) _tool_c89cc_glob_add "$_name" 8 "$_decl_esize";;     # global
			*) _tool_c89cc_alloc_local; _tool_c89cc_sym_add "$_name" "local" "$REPLY" "$_decl_esize";;
			esac;;
		*)
			_tool_c89cc_type "$_rest"; local _rest_t=$REPLY
			case "$_rest_t" in
			C1) # func_def
				_tool_c89cc_func "$_name" "$_rest";;
			C5) # init_part (= initializer)
				case "$_SCOPE" in
				0) # Global with initializer — TODO: static init
					_tool_c89cc_glob_add "$_name" 8 "$_decl_esize";;
				*)
					_tool_c89cc_alloc_local
					local _off=$REPLY
					_tool_c89cc_sym_add "$_name" "local" "$_off" "$_decl_esize"
					# Скомпилировать выражение инициализатора
					_tool_c89cc_children "$_rest"
					local _init_expr="${REPLY%% *}"
					_tool_c89cc_expr "$_init_expr"
					# Сохранить rax в локальную переменную
					_tool_c89cc_store_local $_off;;
				esac;;
			Cz) # after_name: could be ; or array or init
				case "$_SCOPE" in
				0) _tool_c89cc_glob_add "$_name" 8 "$_decl_esize";;
				*) _tool_c89cc_alloc_local; _tool_c89cc_sym_add "$_name" "local" "$REPLY" "$_decl_esize";;
				esac;;
			*) # Other (more_decls, etc.)
				case "$_SCOPE" in
				0) _tool_c89cc_glob_add "$_name" 8 "$_decl_esize";;
				*) _tool_c89cc_alloc_local; _tool_c89cc_sym_add "$_name" "local" "$REPLY" "$_decl_esize";;
				esac;;
			esac;;
		esac;;

	Cw) # decl_rest — delegate (pass esize through)
		_tool_c89cc_children "$_child"
		case "$REPLY" in ?*) _tool_c89cc_decl "$_type_code" "$REPLY" "$_decl_esize";; esac;;

	Cx) # ptr_decl — pointer type, delegate to inner (pass esize through)
		_tool_c89cc_children "$_child"
		case "$REPLY" in ?*) _tool_c89cc_decl "$_type_code" "$REPLY" "$_decl_esize";; esac;;

	*) ;; # skip unknown
	esac
}

# Поиск смещения поля по имени поля.
# Использует реестр структур, если доступен, иначе возвращается к последовательным 8-байтовым смещениям.
_tool_c89cc_field_off () {
	local _fname=$1
	# Сначала проверить реестр структур
	local _si=1
	while test $_si -le $_STRUCT_N; do
		local _j=1 _off=0 _nf
		eval "_nf=\$_STRUCT_NFIELDS_$_si"
		while test $_j -le $_nf; do
			eval "local _fn=\"\$_STRUCT_FNAME_${_si}_${_j}\""
			case "$_fn" in "$_fname") REPLY=$_off; return;; esac
			eval "local _fs=\$_STRUCT_FSIZE_${_si}_${_j}"
			_off=$(( (_off + _fs + 7) & -8 ))  # align to 8
			_j=$((_j + 1))
		done
		_si=$((_si + 1))
	done
	# Запасной вариант: предположить последовательные 8-байтовые поля
	REPLY=0
}

# Подсчет глубины указателя в узле AST параметра (количество уровней *)
_tool_c89cc_ptr_depth () {
	local _pdn=$1 _depth=0 _pdt
	_tool_c89cc_children "$_pdn"
	local _pd_chs="$REPLY"
	for _pdc in $_pd_chs; do
		_tool_c89cc_type "$_pdc"; _pdt=$REPLY
		case "$_pdt" in
		C10) # param_ptr: count this * and recurse
			_tool_c89cc_ptr_depth "$_pdc"
			_depth=$((_depth + 1 + REPLY))
			REPLY=$_depth; return;;
		C9) # param_rest: recurse
			_tool_c89cc_ptr_depth "$_pdc"
			_depth=$((_depth + REPLY))
			REPLY=$_depth; return;;
		esac
	done
	REPLY=$_depth
}

# Извлечение имени параметра из узла AST параметра (обходит цепочки param_ptr)
_tool_c89cc_param_name () {
	local _pn=$1 _pt
	_tool_c89cc_children "$_pn"
	local _pn_chs="$REPLY"
	REPLY=
	for _pc in $_pn_chs; do
		_tool_c89cc_type "$_pc"; _pt=$REPLY
		case "$_pt" in
		C48) _tool_c89cc_val "$_pc"; return;;        # direct ident
		C10|C9) _tool_c89cc_param_name "$_pc"; return;; # param_ptr or param_rest: recurse
		esac
	done
}

# ============================================================
# Компилятор функций
# ============================================================
_tool_c89cc_func () {
	local _name=$1 _fdef_node=$2
	local _saved_frame=$_FRAME_SIZE _saved_sym=$_SYM_N

	# Проверить, является ли это определением (имеет func_block) или просто объявлением
	_tool_c89cc_children "$_fdef_node"
	local _fd_chs="$REPLY" _params= _body=
	for _ch in $_fd_chs; do
		_tool_c89cc_type "$_ch"
		case "$REPLY" in
		C3) _body=$_ch;;       # func_block
		C8) _params="$_params $_ch";;  # param
		esac
	done

	# Если нет тела, это предварительное объявление — пропустить генерацию кода
	case "$_body" in '') return;; esac

	_tool_c89cc_label "$_name"

	case "$_name" in
	"запуск")
		_tool_c89cc_label "main"
		;;
	esac

	_FRAME_SIZE=0
	_SCOPE=$((_SCOPE + 1))

	# Пролог функции
	_tool_c89cc_emit "55"                # push rbp
	_tool_c89cc_emit "48 89 E5"          # mov rbp, rsp

	# Зарезервировать место для sub rsp — мы исправим это позже
	local _sub_rsp_pos=$_IP
	_tool_c89cc_emit "48 81 EC"          # sub rsp, imm32
	_tool_c89cc_emit "00 00 00 00"       # placeholder (patched after body)

	# Выделить параметры как локальные переменные (System V ABI: rdi, rsi, rdx, rcx, r8, r9)
	local _pi=0
	for _p in $_params; do
		_pi=$((_pi + 1))
		# Получить имя параметра (может быть вложено в цепочки param_ptr)
		_tool_c89cc_param_name "$_p"
		local _pname=$REPLY
		case "$_pname" in '') _pname="_param_$_pi";; esac

		# Определить тип параметра и глубину указателя для размера элемента
		local _param_esize=8 _param_ptrdepth=0 _base_type=int
		_tool_c89cc_children "$_p"
		local _p_chs="$REPLY"
		for _ptc in $_p_chs; do
			_tool_c89cc_type "$_ptc"
			case "$REPLY" in
			C11) _tool_c89cc_val "$_ptc"; _base_type=$REPLY;;
			esac
		done
		# Подсчет глубины указателя путем обхода цепочки param_ptr
		_tool_c89cc_ptr_depth "$_p"; _param_ptrdepth=$REPLY
		# char* с 1 указателем → байтовые элементы; все остальное → 8
		case "$_base_type" in char)
			case "$_param_ptrdepth" in 1) _param_esize=1;; esac;; esac

		_tool_c89cc_alloc_local
		_tool_c89cc_sym_add "$_pname" "param" "$REPLY" "$_param_esize"
		local _off=$REPLY

		# Копировать аргумент регистра в стек (mod=01 для disp8, mod=10 для disp32)
		if test $_off -le 127; then
			case $_pi in
			1) _tool_c89cc_emit "48 89 7D";; 2) _tool_c89cc_emit "48 89 75";;
			3) _tool_c89cc_emit "48 89 55";; 4) _tool_c89cc_emit "48 89 4D";;
			5) _tool_c89cc_emit "4C 89 45";; 6) _tool_c89cc_emit "4C 89 4D";;
			esac
		else
			case $_pi in
			1) _tool_c89cc_emit "48 89 BD";; 2) _tool_c89cc_emit "48 89 B5";;
			3) _tool_c89cc_emit "48 89 95";; 4) _tool_c89cc_emit "48 89 8D";;
			5) _tool_c89cc_emit "4C 89 85";; 6) _tool_c89cc_emit "4C 89 8D";;
			esac
		fi
		_tool_c89cc_emit_off $_off
	done

	# Скомпилировать тело функции
	case "$_body" in ?*)
		_tool_c89cc_children "$_body"; local _fb_chs="$REPLY"
		for _ch in $_fb_chs; do _tool_c89cc_node "$_ch"; done;;
	esac

	# Возврат по умолчанию (на случай отсутствия явного return)
	_tool_c89cc_emit "48 31 C0"          # xor rax, rax (return 0)
	_tool_c89cc_emit "C9"                # leave
	_tool_c89cc_emit "C3"                # ret

	# Исправить sub rsp на актуальный размер кадра (выровнять по 16)
	local _aligned=$(( (_FRAME_SIZE + 15) & -16 ))
	_tool_c89cc_patch_le32 $((_sub_rsp_pos + 3)) $_aligned

	# Восстановить область видимости
	_SCOPE=$((_SCOPE - 1))
	_SYM_N=$_saved_sym
	_FRAME_SIZE=$_saved_frame
}

# ============================================================
# Компилятор Lvalue (адрес выражения в %rax)
# ============================================================
_tool_c89cc_lvalue () {
	local _n=$1 _t _v
	_tool_c89cc_type "$_n"; _t=$REPLY
	_tool_c89cc_val "$_n"; _v=$REPLY

	case "$_t" in
	C39) # expr: delegate
		_tool_c89cc_children "$_n"
		_tool_c89cc_lvalue "$REPLY";;
	C48) # ident: address of variable
		case "$_v" in
		[0-9]*) echo "ERROR: cannot take address of number" >&2;;
		*)
			if _tool_c89cc_sym_find "$_v"; then
				local _lv_rest="$REPLY"
				local _kind="${_lv_rest%% *}"; _lv_rest="${_lv_rest#* }"
				local _off="${_lv_rest%% *}"
				case "$_kind" in
				global)
					_tool_c89cc_emit "48 B8"
					_RELOCS="$_RELOCS G${_IP}=GLOB${_off}"
					_tool_c89cc_emit "00 00 00 00 00 00 00 00";;
				*)
					_tool_c89cc_lea_local $_off;;
				esac
			else
				echo "ERROR: undefined variable for lvalue: $_v" >&2
			fi;;
		esac;;
	C52) # *expr: address is the pointer value itself
		_tool_c89cc_children "$_n"
		_tool_c89cc_expr "$REPLY";;
	C58) # a[i]: address = base + index * elem_size
		_tool_c89cc_children "$_n"
		local _ab="${REPLY%% *}" _ai="${REPLY#* }"
		local _lv_esize=8
		_tool_c89cc_val "$_ab"
		case "$REPLY" in [a-zA-Z_]*)
			if _tool_c89cc_sym_find "$REPLY"; then
				local _le_rest="$REPLY"
				_le_rest="${_le_rest#* }"; _le_rest="${_le_rest#* }"
				_lv_esize="${_le_rest%% *}"
			fi;; esac
		_tool_c89cc_expr "$_ab"
		_tool_c89cc_emit "50"
		_tool_c89cc_expr "$_ai"
		case "$_lv_esize" in
		1) ;;
		2) _tool_c89cc_emit "48 C1 E0 01";;
		4) _tool_c89cc_emit "48 C1 E0 02";;
		8) _tool_c89cc_emit "48 C1 E0 03";;
		esac
		_tool_c89cc_emit "59"
		_tool_c89cc_emit "48 01 C8";;
	C60) # s.field: address = &s + offset
		_tool_c89cc_children "$_n"
		local _sb="${REPLY%% *}" _sf="${REPLY#* }"
		_tool_c89cc_lvalue "$_sb"
		_tool_c89cc_val "$_sf"; local _sfn=$REPLY
		_tool_c89cc_field_off "$_sfn"
		case "$REPLY" in 0) ;; *)
			_tool_c89cc_emit "48 05"; _tool_c89cc_emit_le32 $REPLY;; esac;;
	C61) # p->field: address = *p + offset
		_tool_c89cc_children "$_n"
		local _pb="${REPLY%% *}" _pf="${REPLY#* }"
		_tool_c89cc_expr "$_pb"                  # rax = pointer value
		_tool_c89cc_val "$_pf"; local _pfn=$REPLY
		_tool_c89cc_field_off "$_pfn"
		case "$REPLY" in 0) ;; *)
			_tool_c89cc_emit "48 05"; _tool_c89cc_emit_le32 $REPLY;; esac;;
	*) echo "ERROR: not an lvalue (type=$_t)" >&2;;
	esac
}

# ============================================================
# Компилятор выражений (результат в %rax)
# ============================================================
_tool_c89cc_expr () {
	local _n=$1 _t _v
	_tool_c89cc_type "$_n"; _t=$REPLY
	_tool_c89cc_val "$_n"; _v=$REPLY

	case "$_t" in
	C39) # expr: delegate to child
		_tool_c89cc_children "$_n"
		_tool_c89cc_expr "$REPLY";;

	C48) # ident or number literal
		case "$_v" in
		[0-9]*) # Number literal
			local _num
			case "$_v" in
			0x*|0X*) _num=$(( _v ));;           # hex
			0[0-7]*) _num=$(( _v ));;            # octal (shell handles)
			*) _num=$_v;;                         # decimal
			esac
			_tool_c89cc_emit "48 C7 C0"                   # mov rax, imm32
			_tool_c89cc_emit_le32 $_num
			;;
		*) # Variable reference — load from stack or global
			if _tool_c89cc_sym_find "$_v"; then
				local _vr_rest="$REPLY"
				local _kind="${_vr_rest%% *}"; _vr_rest="${_vr_rest#* }"
				local _off="${_vr_rest%% *}"
				case "$_kind" in
				global)
					_tool_c89cc_emit "48 B8"
					_RELOCS="$_RELOCS G${_IP}=GLOB${_off}"
					_tool_c89cc_emit "00 00 00 00 00 00 00 00"
					_tool_c89cc_emit "48 8B 00";;
				*)
					_tool_c89cc_load_local $_off;;
				esac
			else
				echo "ERROR: undefined variable: $_v" >&2
			fi;;
		esac;;

	C55) # binary operator (precedence climbing)
		_tool_c89cc_children "$_n"
		local _lhs="${REPLY%% *}" _rhs="${REPLY#* }"
		# Скомпилировать левый операнд
		_tool_c89cc_expr "$_lhs"
		_tool_c89cc_emit "50"                # push rax (save left)
		# Скомпилировать правый операнд
		_tool_c89cc_expr "$_rhs"
		_tool_c89cc_emit "48 89 C1"          # mov rcx, rax (right in rcx)
		_tool_c89cc_emit "58"                # pop rax (left in rax)
		# Применить оператор
		case "$_v" in
		'+')  _tool_c89cc_emit "48 01 C8";;           # add rax, rcx
		'-')  _tool_c89cc_emit "48 29 C8";;           # sub rax, rcx
		'*')  _tool_c89cc_emit "48 0F AF C1";;        # imul rax, rcx
		'/')  _tool_c89cc_emit "48 99"                # cqo (sign-extend rax → rdx:rax)
		      _tool_c89cc_emit "48 F7 F9";;           # idiv rcx
		'%')  _tool_c89cc_emit "48 99"                # cqo
		      _tool_c89cc_emit "48 F7 F9"             # idiv rcx
		      _tool_c89cc_emit "48 89 D0";;           # mov rax, rdx (remainder)
		'&')  _tool_c89cc_emit "48 21 C8";;           # and rax, rcx
		'|')  _tool_c89cc_emit "48 09 C8";;           # or rax, rcx
		'^')  _tool_c89cc_emit "48 31 C8";;           # xor rax, rcx
		'<<') _tool_c89cc_emit "48 D3 E0";;           # shl rax, cl
		'>>') _tool_c89cc_emit "48 D3 E8";;           # shr rax, cl
		'==') _tool_c89cc_emit "48 39 C8"             # cmp rax, rcx
		      _tool_c89cc_emit "0F 94 C0"             # sete al
		      _tool_c89cc_emit "48 0F B6 C0";;        # movzx rax, al
		'!=') _tool_c89cc_emit "48 39 C8"
		      _tool_c89cc_emit "0F 95 C0"             # setne al
		      _tool_c89cc_emit "48 0F B6 C0";;
		'<')  _tool_c89cc_emit "48 39 C8"
		      _tool_c89cc_emit "0F 9C C0"             # setl al
		      _tool_c89cc_emit "48 0F B6 C0";;
		'>')  _tool_c89cc_emit "48 39 C8"
		      _tool_c89cc_emit "0F 9F C0"             # setg al
		      _tool_c89cc_emit "48 0F B6 C0";;
		'<=') _tool_c89cc_emit "48 39 C8"
		      _tool_c89cc_emit "0F 9E C0"             # setle al
		      _tool_c89cc_emit "48 0F B6 C0";;
		'>=') _tool_c89cc_emit "48 39 C8"
		      _tool_c89cc_emit "0F 9D C0"             # setge al
		      _tool_c89cc_emit "48 0F B6 C0";;
		'=')  # Assignment: compute lvalue address, store rvalue
		      # rcx = правое значение. Теперь вычислить левый адрес и сохранить.
		      _tool_c89cc_emit "51"              # push rcx (save rvalue)
		      _tool_c89cc_lvalue "$_lhs"         # rax = address of lvalue
		      _tool_c89cc_emit "59"              # pop rcx (restore rvalue)
		      # Байтовая запись для *ptr и ptr[i] для char; 8-байтовая для переменных
		      _tool_c89cc_resolve_esize "$_lhs"; local _asgn_esz=$REPLY
		      # Но обычные переменные всегда получают 8-байтовую запись (стековые слоты имеют 8 байт)
		      # Использовать байтовую запись только когда LHS является разыменованием (*p) или индексированием (a[i])
		      local _asgn_inner=$_lhs
		      _tool_c89cc_type "$_asgn_inner"
		      case "$REPLY" in C39) _tool_c89cc_children "$_asgn_inner"; _asgn_inner=$REPLY; _tool_c89cc_type "$_asgn_inner";; esac
		      case "$REPLY" in
		      C52|C58) # deref or subscript: use resolved esize
		           case "$_asgn_esz" in
		           1) _tool_c89cc_emit "88 08";;      # mov [rax], cl (byte store)
		           *) _tool_c89cc_emit "48 89 08";;   # mov [rax], rcx (qword store)
		           esac;;
		      *) _tool_c89cc_emit "48 89 08";;        # mov [rax], rcx (qword store)
		      esac
		      _tool_c89cc_emit "48 89 C8";;      # mov rax, rcx (returns value)
		'+='|'-='|'*='|'/='|'%='|'&='|'|='|'^='|'<<='|'>>=')
		      # Составное присваивание: загрузить текущее, применить оператор, сохранить обратно
		      _tool_c89cc_emit "51"              # push rcx (save rvalue)
		      _tool_c89cc_lvalue "$_lhs"         # rax = address of lvalue
		      _tool_c89cc_emit "50"              # push rax (save address)
		      _tool_c89cc_emit "48 8B 00"        # mov rax, [rax] (load current)
		      _tool_c89cc_emit "5A"              # pop rdx (address in rdx)
		      _tool_c89cc_emit "59"              # pop rcx (rvalue)
		      local _base_op="${_v%=}"
		      case "$_base_op" in
		      '+')  _tool_c89cc_emit "48 01 C8";;
		      '-')  _tool_c89cc_emit "48 29 C8";;
		      '*')  _tool_c89cc_emit "48 0F AF C1";;
		      '/')  _tool_c89cc_emit "48 99"; _tool_c89cc_emit "48 F7 F9";;
		      '%')  _tool_c89cc_emit "48 99"; _tool_c89cc_emit "48 F7 F9"; _tool_c89cc_emit "48 89 D0";;
		      '&')  _tool_c89cc_emit "48 21 C8";;
		      '|')  _tool_c89cc_emit "48 09 C8";;
		      '^')  _tool_c89cc_emit "48 31 C8";;
		      '<<') _tool_c89cc_emit "48 D3 E0";;
		      '>>') _tool_c89cc_emit "48 D3 E8";;
		      esac
		      _tool_c89cc_emit "48 89 02"        # mov [rdx], rax (store result)
		      ;;
		'&&') # Logical AND: short-circuit
		      # Левое в rax. Если 0, пропустить правое.
		      _tool_c89cc_emit "48 85 C0"             # test rax, rax
		      _tool_c89cc_emit "0F 84"                # je <skip>
		      local _and_skip=$_IP
		      _tool_c89cc_emit "00 00 00 00"
		      _tool_c89cc_expr "$_rhs"                # evaluate right
		      # Нормализовать до 0/1
		      _tool_c89cc_emit "48 85 C0"             # test rax, rax
		      _tool_c89cc_emit "0F 95 C0"             # setne al
		      _tool_c89cc_emit "48 0F B6 C0"          # movzx rax, al
		      local _and_end=$_IP
		      _tool_c89cc_patch_le32 $_and_skip $(( _and_end - (_and_skip + 4) ))
		      # Если пропущено, rax равен 0 (левое было 0). Результат верен.
		      ;;
		'||') # Logical OR: short-circuit
		      _tool_c89cc_emit "48 85 C0"             # test rax, rax
		      _tool_c89cc_emit "0F 85"                # jne <skip>
		      local _or_skip=$_IP
		      _tool_c89cc_emit "00 00 00 00"
		      _tool_c89cc_expr "$_rhs"                # evaluate right
		      local _or_end=$_IP
		      _tool_c89cc_patch_le32 $_or_skip $(( _or_end - (_or_skip + 4) ))
		      # Нормализовать до 0/1
		      _tool_c89cc_emit "48 85 C0"             # test rax, rax
		      _tool_c89cc_emit "0F 95 C0"             # setne al
		      _tool_c89cc_emit "48 0F B6 C0"          # movzx rax, al
		      ;;
		esac;;

	C56) # Function call postfix: fn(args)
		_tool_c89cc_children "$_n"
		local _fn_node="${REPLY%% *}" _arg_node="${REPLY#* }"
		case "$_arg_node" in "$REPLY") _arg_node=;; esac
		_tool_c89cc_val "$_fn_node"; local _fn_name=$REPLY

		# Скомпилировать аргументы и поместить их в стек
		local _argc=0 _argi=0
		case "$_arg_node" in ?*)
			_tool_c89cc_children "$_arg_node"; local _arg_chs="$REPLY"
			# Подсчитать и скомпилировать аргументы (помещать в стек в обратном порядке, но использовать регистры)
			for _a in $_arg_chs; do _argc=$((_argc + 1)); done
			# Скомпилировать каждый аргумент, поместить в стек
			for _a in $_arg_chs; do
				_tool_c89cc_expr "$_a"
				_tool_c89cc_emit "50"         # push rax
			done;;
		esac

		# __syscall встроенная функция: syscall(nr, a1, a2, a3, a4, a5, a6)
		# Использует: rax=nr, rdi=a1, rsi=a2, rdx=a3, r10=a4, r8=a5, r9=a6
		case "$_fn_name" in __syscall)
			_argi=$_argc
			while test $_argi -gt 0; do
				case $_argi in
				1) _tool_c89cc_emit "58";;       # pop rax (syscall number)
				2) _tool_c89cc_emit "5F";;       # pop rdi (arg1)
				3) _tool_c89cc_emit "5E";;       # pop rsi (arg2)
				4) _tool_c89cc_emit "5A";;       # pop rdx (arg3)
				5) _tool_c89cc_emit "41 5A";;    # pop r10 (arg4)
				6) _tool_c89cc_emit "41 58";;    # pop r8 (arg5)
				7) _tool_c89cc_emit "41 59";;    # pop r9 (arg6)
				esac
				_argi=$((_argi - 1))
			done
			_tool_c89cc_emit "0F 05";;           # syscall; result in rax
		*)
			# Извлечь аргументы в регистры (порядок System V ABI)
			_argi=$_argc
			while test $_argi -gt 0; do
				case $_argi in
				1) _tool_c89cc_emit "5F";;       # pop rdi (1st arg)
				2) _tool_c89cc_emit "5E";;       # pop rsi (2nd arg)
				3) _tool_c89cc_emit "5A";;       # pop rdx (3rd arg)
				4) _tool_c89cc_emit "59";;       # pop rcx (4th arg)
				5) _tool_c89cc_emit "41 58";;    # pop r8 (5th arg)
				6) _tool_c89cc_emit "41 59";;    # pop r9 (6th arg)
				*) ;; # leave on stack for >6 args
				esac
				_argi=$((_argi - 1))
			done

			# Вызвать функцию
			_tool_c89cc_emit "E8"                # call <rel32>
			_tool_c89cc_reloc_rel32 "$_fn_name"
			# Результат в rax
		;; esac
		;;

	C49|C50|C51|C52|C53|C54) # unary operators
		_tool_c89cc_children "$_n"
		case "$_t" in
		C52) # unary * (dereference): compute address, then load
		     local _deref_child="$REPLY" _deref_esz=8
		     _tool_c89cc_resolve_esize "$_deref_child"; _deref_esz=$REPLY
		     _tool_c89cc_expr "$_deref_child"
		     case "$_deref_esz" in
		     1) _tool_c89cc_emit "48 0F B6 00";;      # movzx rax, byte [rax]
		     *) _tool_c89cc_emit "48 8B 00";;          # mov rax, [rax]
		     esac;;
		C53) # unary & (address-of): compute lvalue address
		     _tool_c89cc_lvalue "$REPLY";;
		*)   # other unary: compute value first
		     _tool_c89cc_expr "$REPLY"
		     case "$_t" in
		     C49) _tool_c89cc_emit "48 F7 D8";;       # neg rax (unary -)
		     C50) # Logical NOT
		          _tool_c89cc_emit "48 85 C0"          # test rax, rax
		          _tool_c89cc_emit "0F 94 C0"          # sete al
		          _tool_c89cc_emit "48 0F B6 C0";;     # movzx rax, al
		     C51) _tool_c89cc_emit "48 F7 D0";;       # not rax (bitwise ~)
		     C54) ;; # unary ++ (pre-increment) — TODO
		     esac;;
		esac;;

	C64) # Ternary operator: cond ? true_expr : false_expr
		_tool_c89cc_children "$_n"
		set -- $REPLY
		local _tc="$1" _tt="$2" _tf="$3"
		_tool_c89cc_expr "$_tc"
		_tool_c89cc_emit "48 85 C0"                   # test rax, rax
		_tool_c89cc_emit_jcc "84"; local _tern_f=$REPLY  # je false_branch
		_tool_c89cc_expr "$_tt"
		_tool_c89cc_emit_jmp; local _tern_e=$REPLY    # jmp end
		_tool_c89cc_jmp_target "$_tern_f"
		_tool_c89cc_expr "$_tf"
		_tool_c89cc_jmp_target "$_tern_e";;

	C58) # Array subscript: a[i] → base + index * elem_size
		_tool_c89cc_children "$_n"
		local _arr_base="${REPLY%% *}" _arr_idx="${REPLY#* }"
		# Определить размер элемента из типа базовой переменной
		local _arr_esize=8
		_tool_c89cc_val "$_arr_base"
		case "$REPLY" in [a-zA-Z_]*)
			if _tool_c89cc_sym_find "$REPLY"; then
				local _ae_rest="$REPLY"
				_ae_rest="${_ae_rest#* }"; _ae_rest="${_ae_rest#* }"  # skip kind, off
				_arr_esize="${_ae_rest%% *}"
			fi;; esac
		_tool_c89cc_expr "$_arr_base"            # base address in rax
		_tool_c89cc_emit "50"                    # push rax
		_tool_c89cc_expr "$_arr_idx"             # index in rax
		case "$_arr_esize" in
		1) ;;                            # no scaling for char
		2) _tool_c89cc_emit "48 C1 E0 01";;     # shl rax, 1
		4) _tool_c89cc_emit "48 C1 E0 02";;     # shl rax, 2
		8) _tool_c89cc_emit "48 C1 E0 03";;     # shl rax, 3
		*) _tool_c89cc_emit "48 6B C0"; _tool_c89cc_emit_d $_arr_esize;; # imul rax, imm8
		esac
		_tool_c89cc_emit "59"                    # pop rcx (base)
		_tool_c89cc_emit "48 01 C8"              # add rax, rcx
		# Загрузка: байт для char, qword для остальных
		case "$_arr_esize" in
		1) _tool_c89cc_emit "48 0F B6 00";;      # movzx rax, byte [rax]
		*) _tool_c89cc_emit "48 8B 00";;         # mov rax, [rax]
		esac;;

	C62) # Postfix ++
		_tool_c89cc_children "$_n"
		_tool_c89cc_lvalue "$REPLY"              # rax = address
		_tool_c89cc_emit "48 8B 08"              # mov rcx, [rax] (old value)
		_tool_c89cc_emit "50"                    # push rax (save address)
		_tool_c89cc_emit "48 8D 41 01"           # lea rax, [rcx+1]
		_tool_c89cc_emit "5A"                    # pop rdx (address)
		_tool_c89cc_emit "48 89 02"              # mov [rdx], rax (store incremented)
		_tool_c89cc_emit "48 89 C8";;            # mov rax, rcx (return OLD value)

	C63) # Postfix --
		_tool_c89cc_children "$_n"
		_tool_c89cc_lvalue "$REPLY"
		_tool_c89cc_emit "48 8B 08"              # mov rcx, [rax]
		_tool_c89cc_emit "50"
		_tool_c89cc_emit "48 8D 41 FF"           # lea rax, [rcx-1]
		_tool_c89cc_emit "5A"
		_tool_c89cc_emit "48 89 02"
		_tool_c89cc_emit "48 89 C8";;

	C60) # Member access: s.field → base + offset
		_tool_c89cc_children "$_n"
		local _dot_base="${REPLY%% *}" _dot_field="${REPLY#* }"
		_tool_c89cc_lvalue "$_dot_base"          # rax = address of struct
		_tool_c89cc_val "$_dot_field"; local _fn60=$REPLY
		local _foff=0
		_tool_c89cc_field_off "$_fn60"; _foff=$REPLY
		# Добавить смещение поля, если не ноль
		case "$_foff" in 0) ;; *)
			_tool_c89cc_emit "48 05"             # add rax, imm32
			_tool_c89cc_emit_le32 $_foff;; esac
		_tool_c89cc_emit "48 8B 00";;            # mov rax, [rax]

	C61) # Arrow access: p->field → deref pointer + field offset
		_tool_c89cc_children "$_n"
		local _arr_base="${REPLY%% *}" _arr_field="${REPLY#* }"
		_tool_c89cc_expr "$_arr_base"            # rax = pointer value (address)
		_tool_c89cc_val "$_arr_field"; local _fn61=$REPLY
		local _foff=0
		_tool_c89cc_field_off "$_fn61"; _foff=$REPLY
		# Добавить смещение поля, если не ноль
		case "$_foff" in 0) ;; *)
			_tool_c89cc_emit "48 05"             # add rax, imm32
			_tool_c89cc_emit_le32 $_foff;; esac
		_tool_c89cc_emit "48 8B 00";;            # mov rax, [rax]

	C45) # String literal
		_tool_c89cc_add_string "$_v"
		local _str_id=$REPLY
		# Загрузить адрес строки: будет исправлено во время генерации ELF
		# Пока: выдать mov rax, imm64 с заполнителем
		_tool_c89cc_emit "48 B8"                 # movabs rax, imm64
		eval "local _soff=\$_STR_OFF_$_str_id"
		# Записать перемещение строки (исправляется после того, как известна раскладка кода+данных)
		_RELOCS="$_RELOCS S${_IP}=STR${_str_id}"
		_tool_c89cc_emit "00 00 00 00 00 00 00 00";;  # placeholder

	C46) # Character literal: 'x' → ASCII value
		local _charval
		case "$_v" in
		'\\n') _charval=10;;
		'\\t') _charval=9;;
		'\\0') _charval=0;;
		'\\\\') _charval=92;;
		"\\'") _charval=39;;
		'\\r') _charval=13;;
		*) _tool_c89cc_c2d "$_v"; _charval=$REPLY;;
		esac
		_tool_c89cc_emit "48 C7 C0"
		_tool_c89cc_emit_le32 $_charval;;

	C43) # Parenthesized expression: ( expr )
		_tool_c89cc_children "$_n"
		_tool_c89cc_expr "$REPLY";;

	C41) # sizeof_expr → compile-time constant
		_tool_c89cc_children "$_n"
		# Дочерние элементы sizeof_body являются именами типов; по умолчанию 8 (размер указателя)
		_tool_c89cc_emit "48 C7 C0"
		_tool_c89cc_emit_le32 8;;

	*) ;; # Unknown — emit 0
	esac
}

# ============================================================
# Генерация заголовка ELF64
# ============================================================
_BASE_ADDR=4194304  # 0x400000
_HDR_SIZE=120       # 64 (ELF) + 56 (1 program header)

_tool_c89cc_write_elf () {
	local _code_size=$_IP
	local _str_size=$(( ${#_STR_DATA} / 2 ))
	local _glob_size=$(( ${#_GLOB_DATA} / 2 ))
	local _data_size=$(( _str_size + _glob_size ))
	local _total_size=$(( _HDR_SIZE + _code_size + _data_size ))
	local _entry=$(( _BASE_ADDR + _HDR_SIZE ))
	# Данные начинаются сразу после кода
	local _str_base=$(( _BASE_ADDR + _HDR_SIZE + _code_size ))
	local _glob_base=$(( _str_base + _str_size ))

	# Заголовок ELF64 (64 байта)
	# e_ident: magic + class + data + version + OS/ABI + выравнивание
	_out_byte 127; _out_byte 69; _out_byte 76; _out_byte 70  # \x7fELF
	_out_byte 2; _out_byte 1; _out_byte 1; _out_byte 0       # 64-bit, LE, v1, SysV
	_out_byte 0; _out_byte 0; _out_byte 0; _out_byte 0       # padding
	_out_byte 0; _out_byte 0; _out_byte 0; _out_byte 0

	# e_type (2) + e_machine (2) + e_version (4)
	_out_byte 2; _out_byte 0                                  # ET_EXEC
	_out_byte 62; _out_byte 0                                 # EM_X86_64
	_out_byte 1; _out_byte 0; _out_byte 0; _out_byte 0       # EV_CURRENT

	# e_entry (8 байт, little-endian)
	_tool_c89cc_le64 $_entry

	# e_phoff (8) = 64 (сразу после заголовка ELF)
	_tool_c89cc_le64 64

	# e_shoff (8) = 0 (нет заголовков секций)
	_tool_c89cc_le64 0

	# e_flags (4) + e_ehsize (2) + e_phentsize (2)
	_out_byte 0; _out_byte 0; _out_byte 0; _out_byte 0       # flags
	_out_byte 64; _out_byte 0                                 # ehsize = 64
	_out_byte 56; _out_byte 0                                 # phentsize = 56

	# e_phnum (2) + e_shentsize (2) + e_shnum (2) + e_shstrndx (2)
	_out_byte 1; _out_byte 0                                  # 1 program header
	_out_byte 0; _out_byte 0                                  # shentsize = 0
	_out_byte 0; _out_byte 0                                  # shnum = 0
	_out_byte 0; _out_byte 0                                  # shstrndx = 0

	# Заголовок программы (56 байт)
	# p_type (4) = PT_LOAD
	_out_byte 1; _out_byte 0; _out_byte 0; _out_byte 0

	# p_flags (4) = PF_R | PF_W | PF_X = 7
	_out_byte 7; _out_byte 0; _out_byte 0; _out_byte 0

	# p_offset (8) = 0 (загрузка с начала файла)
	_tool_c89cc_le64 0

	# p_vaddr (8) = базовый адрес
	_tool_c89cc_le64 $_BASE_ADDR

	# p_paddr (8) = то же самое
	_tool_c89cc_le64 $_BASE_ADDR

	# p_filesz (8) = общий размер файла
	_tool_c89cc_le64 $_total_size

	# p_memsz (8) = то же самое (BSS пока нет)
	_tool_c89cc_le64 $_total_size

	# p_align (8) = 0x1000
	_tool_c89cc_le64 4096

	# Секция кода
	_tool_c89cc_write_code

	# Секция строковых данных
	case "$_STR_DATA" in ?*) _tool_c89cc_write_hex_str "$_STR_DATA";; esac

	# Секция глобальных данных
	case "$_GLOB_DATA" in ?*) _tool_c89cc_write_hex_str "$_GLOB_DATA";; esac
}

# Записать 64-битное значение little-endian как сырые байты
_tool_c89cc_le64 () {
	local _v=$1 _i=0
	while test $_i -lt 8; do
		_out_byte $(( _v % 256 ))
		_v=$(( _v / 256 ))
		_i=$((_i + 1))
	done
}

# Преобразовать 2-символьный шестнадцатеричный в десятичный. Результат в REPLY.
_tool_c89cc_hex2dec () {
	local _h1="${1%?}" _h2="${1#?}" _d1 _d2
	case "$_h1" in
	0) _d1=0;; 1) _d1=1;; 2) _d1=2;; 3) _d1=3;; 4) _d1=4;;
	5) _d1=5;; 6) _d1=6;; 7) _d1=7;; 8) _d1=8;; 9) _d1=9;;
	[Aa]) _d1=10;; [Bb]) _d1=11;; [Cc]) _d1=12;;
	[Dd]) _d1=13;; [Ee]) _d1=14;; [Ff]) _d1=15;; esac
	case "$_h2" in
	0) _d2=0;; 1) _d2=1;; 2) _d2=2;; 3) _d2=3;; 4) _d2=4;;
	5) _d2=5;; 6) _d2=6;; 7) _d2=7;; 8) _d2=8;; 9) _d2=9;;
	[Aa]) _d2=10;; [Bb]) _d2=11;; [Cc]) _d2=12;;
	[Dd]) _d2=13;; [Ee]) _d2=14;; [Ff]) _d2=15;; esac
	REPLY=$(( _d1 * 16 + _d2 ))
}


# Записать буфер кода как сырые байты
_tool_c89cc_write_code () {
	local _i=0
	while test $_i -lt $_IP; do
		eval "_tool_c89cc_hex2dec \"\$_CB_$_i\""
		_out_byte "$REPLY"
		_i=$((_i + 1))
	done
}

# Записать строку из шестнадцатеричных пар как сырые байты (для секций строковых/глобальных данных)
_tool_c89cc_write_hex_str () {
	local _s="${1:-}" _c1 _c2
	while test ${#_s} -gt 0; do
		_c1="${_s%"${_s#?}"}"; _s="${_s#?}"
		_c2="${_s%"${_s#?}"}"; _s="${_s#?}"
		_tool_c89cc_hex2dec "$_c1$_c2"
		_out_byte "$REPLY"
	done
}

# ============================================================
# Точка входа
# ============================================================
_tool_c89cc_init () {
	# Обеспечить работу разделения слов для циклов for
	IFS=' '

	# Зарегистрировать общие раскладки структур (для совместимости с hex2)
	_tool_c89cc_struct_def "input_files"
	_tool_c89cc_struct_field "next" 8
	_tool_c89cc_struct_field "filename" 8
	_tool_c89cc_struct_def "entry"
	_tool_c89cc_struct_field "next" 8
	_tool_c89cc_struct_field "target" 8
	_tool_c89cc_struct_field "name" 8
}

# ============================================================
# Точка входа
# ============================================================
cc_c89 () {
	# Чтение AST из stdin (построчно, чтобы избежать ограничений размера eval)
	while IFS='' read -r _ast_line; do eval "$_ast_line"; done
	case "${_ast_line:-}" in ?*) eval "$_ast_line";; esac

	_tool_c89cc_init

	# Режим ELF: выдать точку входа _start
	_tool_c89cc_label "_start"
	_tool_c89cc_emit "E8"; _tool_c89cc_reloc_rel32 "main"
	_tool_c89cc_emit "48 89 C7"
	_tool_c89cc_emit "48 C7 C0"; _tool_c89cc_emit_le32 60
	_tool_c89cc_emit "0F 05"
	_tool_c89cc_node 0
	_tool_c89cc_fixup
	_tool_c89cc_write_elf
}

tool_c89cc () { cc_c89; }

# --- core/footer.sh ---
# Исправление для ksh93: переобъявление функций через eval.
# В ksh93 функции, определенные через `. file`, не получают расширение алиасов.
# Переобъявление через eval исправляет это. Два режима:
# - Динамическая область видимости (POSIX name(){}): функции, которые читают/записывают
# переменные вызывающей области видимости (_LN, _COL, _SRC*, CONSUMED, V*, X* и т.д.)
# или точки входа, чьи локальные переменные должны быть видны вызываемым (парсеры, генераторы, тесты).
# - Статическая область видимости (AT&T function name {}): все остальное, особенно
# рекурсивные эмиттеры (_*_emit), которым нужны изолированные локальные переменные на кадр вызова.
# Соглашение: новые утилитарные функции (str_*, io_*, ds_*, codegen_*, opt_*)
# используют только свои собственные локальные переменные + REPLY, поэтому статическая область видимости (по умолчанию) верна.
_Ldefn_fix=
eval "_Ldefn_fix(){ typeset _Ldefn_fix=local;} 2>/dev/null"
_Ldefn_fix 2>/dev/null || :
case $_Ldefn_fix in "local")
	_Ldefn_fix () {
		case "$1" in _Ldefn_fix) return;; esac
		_Ldefn_fix="$(typeset -f "$1" 2>/dev/null)" || return 0
		_Ldefn_fix="${_Ldefn_fix#*\{}"
		case "$1" in
		*_parser|ast_out|_error|_nlcount|_numck|_ast_core_pars_epilogue)
			eval "$1 () {${_Ldefn_fix}" 2>/dev/null || :;;
		gen_*|test_*|unit_*|integration_*|full_*)
			eval "$1 () {${_Ldefn_fix}" 2>/dev/null || :;;
		_bnf_gen_*|_shell_common_stripq|_shell_common_shdelim)
			eval "$1 () {${_Ldefn_fix}" 2>/dev/null || :;;
		*)
			eval "function $1 {${_Ldefn_fix}" 2>/dev/null || :;;
		esac
	}
	IFS='
'
	for _Ldefn_fix in $(typeset +f); do
		_Ldefn_fix "${_Ldefn_fix%%"()"*}"
	done
	IFS=''
	;;
esac
unset _Ldefn_fix
unset -f _Ldefn_fix 2>/dev/null || :

# --- встроенная libc.c ---
_BUILTIN_LIBC='

/* ============================================================
 * Русские аналоги функций вывода
 * ============================================================ */

/* принт - аналог sys_write */
int печать(int fd, char *buf, int count) {
    return __syscall(1, fd, buf, count);
}

/* печать_цел - аналог print_int */
void печать_цел(int n) {
    if (n < 0) {
        putchar(45);
        print_uint(0 - n);
    } else {
        print_uint(n);
    }
}

/* длина_строки - аналог strlen */
int длина_строки(char *s) {
    int n = 0;
    while (*s) { n += 1; s = s + 1; }
    return n;
}


/* ============================================================
 * Mini-libc: syscall-only C library for x86-64 Linux
 * ============================================================
 * No external dependencies. Compiled by gen/c89cc.sh.
 *
 * Build: printf '\'''\'' | cat lib/libc.c YOURPROG.c | sh gen/c89.sh | sh gen/c89cc.sh > a.out
 */

/* ============================================================
 * Syscall wrappers
 * ============================================================
 * Linux x86-64 syscall numbers from <asm/unistd_64.h>
 */

int sys_read(int fd, char *buf, int count) {
	return __syscall(0, fd, buf, count);
}

int sys_write(int fd, char *buf, int count) {
	return __syscall(1, fd, buf, count);
}

int sys_open(char *path, int flags, int mode) {
	return __syscall(2, path, flags, mode);
}

int sys_close(int fd) {
	return __syscall(3, fd);
}

int sys_brk(int addr) {
	return __syscall(12, addr);
}

int sys_pipe(int *fds) {
	return __syscall(22, fds);
}

int sys_dup2(int oldfd, int newfd) {
	return __syscall(33, oldfd, newfd);
}

int sys_fork() {
	return __syscall(57);
}

int sys_execve(char *path, char **argv, char **envp) {
	return __syscall(59, path, argv, envp);
}

int sys_exit(int code) {
	return __syscall(60, code);
}

int sys_wait4(int pid, int *status, int options, int rusage) {
	return __syscall(61, pid, status, options, rusage);
}

int sys_getcwd(char *buf, int size) {
	return __syscall(79, buf, size);
}

int sys_chdir(char *path) {
	return __syscall(80, path);
}

/* ============================================================
 * String operations
 * ============================================================ */

int strlen(char *s) {
	int n = 0;
	while (*s) { n += 1; s = s + 1; }
	return n;
}

int strcmp(char *a, char *b) {
	while (*a && *a == *b) { a = a + 1; b = b + 1; }
	return *a - *b;
}

int strncmp(char *a, char *b, int n) {
	while (n > 0 && *a && *a == *b) { a = a + 1; b = b + 1; n -= 1; }
	if (n == 0) return 0;
	return *a - *b;
}

char *strcpy(char *dst, char *src) {
	char *d = dst;
	while (*src) { *d = *src; d = d + 1; src = src + 1; }
	*d = 0;
	return dst;
}

char *strcat(char *dst, char *src) {
	char *d = dst;
	while (*d) d = d + 1;
	while (*src) { *d = *src; d = d + 1; src = src + 1; }
	*d = 0;
	return dst;
}

char *strchr(char *s, int c) {
	while (*s) {
		if (*s == c) return s;
		s = s + 1;
	}
	if (c == 0) return s;
	return 0;
}

char *memcpy(char *dst, char *src, int n) {
	char *d = dst;
	while (n > 0) { *d = *src; d = d + 1; src = src + 1; n -= 1; }
	return dst;
}

char *memset(char *dst, int c, int n) {
	char *d = dst;
	while (n > 0) { *d = c; d = d + 1; n -= 1; }
	return dst;
}

/* ============================================================
 * Memory allocator (bump + free-list via brk)
 * ============================================================
 * Each allocation has an 8-byte header storing the usable size.
 * free() returns blocks to a binned free-list (10 size classes:
 * 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096).
 * malloc() checks the free-list before bumping the heap.
 */

int _heap_start;
int _heap_cur;
int _heap_end;

/* Free-list bins: 10 classes (8..4096), each a singly-linked list.
 * Freed blocks store the "next" pointer in their first 8 bytes.
 * Allocated at first malloc call (can'\''t use global array, compiler
 * allocates only 8 bytes per global regardless of array size). */
int *_free_bins;

int _size_class(int size) {
	/* Return bin index for 8-aligned size, or -1 if too large */
	int bin; int s;
	bin = 0; s = 8;
	while (s < size) { s = s * 2; bin = bin + 1; if (bin >= 10) return -1; }
	return bin;
}

int malloc(int size) {
	int cur;
	int new_end;
	int *hp;
	int bin;
	if (_heap_start == 0) {
		_heap_start = sys_brk(0);
		_heap_cur = _heap_start;
		_heap_end = sys_brk(_heap_start + 8388608);
		/* Allocate free-list bins (10 entries, zeroed) */
		_free_bins = _heap_cur;
		_heap_cur = _heap_cur + 80;
		bin = 0; while (bin < 10) { _free_bins[bin] = 0; bin = bin + 1; }
	}
	size = (size + 7) & -8;
	bin = _size_class(size);
	if (bin >= 0) {
		cur = _free_bins[bin];
		if (cur != 0) {
			hp = cur;
			_free_bins[bin] = hp[0];
			hp = cur - 8;
			hp[0] = size;
			return cur;
		}
	}
	/* Bump allocate with 8-byte size header */
	cur = _heap_cur;
	_heap_cur = cur + size + 8;
	if (_heap_cur > _heap_end) {
		new_end = _heap_cur + 16777216;
		_heap_end = sys_brk(new_end);
	}
	hp = cur;
	hp[0] = size;
	return cur + 8;
}

void free(char *ptr) {
	int size;
	int bin;
	int *hp;
	if (ptr == 0) return;
	/* Only free heap-allocated pointers (skip string literals, etc.) */
	if (ptr <= _heap_start || ptr >= _heap_cur) return;
	hp = ptr - 8;
	size = hp[0];           /* read header */
	bin = _size_class(size);
	if (bin < 0) return;    /* oversized: leak */
	hp = ptr;
	hp[0] = _free_bins[bin]; /* store next ptr in block */
	_free_bins[bin] = ptr;
}

/* ============================================================
 * Temporary arena (bulk-reset between commands)
 * ============================================================ */

int _tmp_base;
int _tmp_cur;
int _tmp_size;

void tmp_init(int size) {
	_tmp_base = malloc(size);
	_tmp_cur = _tmp_base;
	_tmp_size = size;
}

int tmp_alloc(int size) {
	int cur;
	size = (size + 7) & -8;
	cur = _tmp_cur;
	_tmp_cur = cur + size;
	if (_tmp_cur > _tmp_base + _tmp_size) {
		_tmp_cur = cur;
		return malloc(size);
	}
	return cur;
}

void tmp_reset() {
	_tmp_cur = _tmp_base;
}

/* ============================================================
 * I/O helpers
 * ============================================================ */

/* Report stack + heap usage to stderr */
void mem_report() {
	int stack_var;
	fputs("MEM: heap=", 2);
	print_int((_heap_cur - _heap_start) / 1024);
	fputs("K stack_approx=", 2);
	/* &stack_var gives approximate stack pointer */
	print_int(&stack_var);
	fputs("\n", 2);
}

int putchar(int c) {
	char buf;
	*(&buf) = c;
	sys_write(1, &buf, 1);
	return c;
}

int puts(char *s) {
	sys_write(1, s, strlen(s));
	putchar(10);
	return 0;
}

int fputs(char *s, int fd) {
	sys_write(fd, s, strlen(s));
	return 0;
}

int getchar() {
	char buf;
	int n;
	n = sys_read(0, &buf, 1);
	if (n <= 0) return -1;
	return *(&buf);
}

/* Print unsigned decimal integer (recursive to avoid local arrays) */
void print_uint(int n) {
	if (n >= 10) print_uint(n / 10);
	putchar(48 + n % 10);
}

/* Print signed decimal integer */
void print_int(int n) {
	if (n < 0) {
		putchar(45);
		print_uint(0 - n);
	} else {
		print_uint(n);
	}
}
'

# --- main ---
_no_libc=0
case "${1:-}" in --no-libc) _no_libc=1; shift;; esac

if test $_no_libc -eq 1; then
    c89_parser | cc_c89
else
    { _printr1 "$_BUILTIN_LIBC"; /bin/cat; } | c89_parser | cc_c89
fi
