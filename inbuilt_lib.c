/* ============================================================
 * Mini-libc: библиотека C только через системные вызовы для x86-64 Linux
 * ============================================================
 * Без внешних зависимостей. Компилируется через gen/c89cc.sh.
 *
 * Сборка: printf '\'''\'' | cat lib/libc.c YOURPROG.c | sh gen/c89.sh | sh gen/c89cc.sh > a.out
 */

/* ============================================================
 * Обёртки системных вызовов
 * ============================================================
 * Номера системных вызовов Linux x86-64 из <asm/unistd_64.h>
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
 * Операции со строками
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
 * Аллокатор памяти (наращивание + список свободных через brk)
 * ============================================================
 * У каждого блока есть 8-байтовый заголовок, хранящий полезный размер.
 * free() возвращает блоки в корзины списка свободных (10 классов размеров:
 * 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096).
 * malloc() проверяет список свободных перед наращиванием кучи.
 */

int _heap_start;
int _heap_cur;
int _heap_end;

/* Корзины списка свободных: 10 классов (8..4096), каждый — односвязный список.
 * Освобождённые блоки хранят указатель "next" в первых 8 байтах.
 * Выделяется при первом вызове malloc (нельзя использовать глобальный массив,
 * компилятор выделяет только 8 байт на глобальную переменную независимо от размера массива). */
int *_free_bins;

int _size_class(int size) {
	/* Возвращает индекс корзины для выровненного на 8 размера, или -1 если слишком велик */
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
		/* Выделяем корзины списка свободных (10 записей, обнулённые) */
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
	/* Наращивание с 8-байтовым заголовком размера */
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
	/* Освобождаем только указатели из кучи (пропускаем строковые литералы и т.п.) */
	if (ptr <= _heap_start || ptr >= _heap_cur) return;
	hp = ptr - 8;
	size = hp[0];           /* читаем заголовок */
	bin = _size_class(size);
	if (bin < 0) return;    /* слишком большой: утечка */
	hp = ptr;
	hp[0] = _free_bins[bin]; /* сохраняем следующий указатель в блоке */
	_free_bins[bin] = ptr;
}

/* ============================================================
 * Временная арена (полный сброс между командами)
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
 * Вспомогательные функции ввода-вывода
 * ============================================================ */

/* Вывести использование стека и кучи в stderr */
void mem_report() {
	int stack_var;
	fputs("MEM: heap=", 2);
	print_int((_heap_cur - _heap_start) / 1024);
	fputs("K stack_approx=", 2);
	/* &stack_var даёт приблизительное значение указателя стека */
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

/* Печать беззнакового десятичного целого (рекурсия для избежания локальных массивов) */
void print_uint(int n) {
	if (n >= 10) print_uint(n / 10);
	putchar(48 + n % 10);
}

/* Печать знакового десятичного целого */
void print_int(int n) {
	if (n < 0) {
		putchar(45);
		print_uint(0 - n);
	} else {
		print_uint(n);
	}
}
