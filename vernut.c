/*
***@***:~/Документы/РуСи$ sh РуСи89cc_ru.sh < vernut.c > vernut.out
DEBUG: ASCII byte: 4D
DEBUG: ASCII byte: 45
DEBUG: ASCII byte: 4D
DEBUG: ASCII byte: 3A
DEBUG: ASCII byte: 20
DEBUG: ASCII byte: 68
DEBUG: ASCII byte: 65
DEBUG: ASCII byte: 61
DEBUG: ASCII byte: 70
DEBUG: ASCII byte: 3D
DEBUG: Final _STR_DATA: 4D454D3A20686561703D00
DEBUG: ASCII byte: 4B
DEBUG: ASCII byte: 20
DEBUG: ASCII byte: 73
DEBUG: ASCII byte: 74
DEBUG: ASCII byte: 61
DEBUG: ASCII byte: 63
DEBUG: ASCII byte: 6B
DEBUG: ASCII byte: 5F
DEBUG: ASCII byte: 61
DEBUG: ASCII byte: 70
DEBUG: ASCII byte: 70
DEBUG: ASCII byte: 72
DEBUG: ASCII byte: 6F
DEBUG: ASCII byte: 78
DEBUG: ASCII byte: 3D
DEBUG: Final _STR_DATA: 4D454D3A20686561703D004B20737461636B5F617070726F783D00
DEBUG: Final _STR_DATA: 4D454D3A20686561703D004B20737461636B5F617070726F783D000A00
***@***:~/Документы/РуСи$ chmod +x vernut.out
***@***:~/Документы/РуСи$ ./vernut.out
***@***:~/Документы/РуСи$ echo "Exit code: $?"
Exit code: 42
*/

int main() {
    вернуть 42;
}
