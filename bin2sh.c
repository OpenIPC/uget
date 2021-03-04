#include <stdio.h>
#include <stdlib.h>

const char *trtable[256] = {
    "\\0", // 0
    NULL, // 1
    NULL, // 2
    NULL, // 3
    NULL, // 4
    NULL, // 5
    NULL, // 6
    "\\a", // 7
    "\\b", // 8
    "\\t", // 9
    "\\n", // 10
    "\\v", // 11
    "\\f", // 12
    "\\r", // 13
};

int printable(char ch) {
  return ch != '`' && ch != '"' && ch != '\\' && (ch >= 'a' && ch <= 'z');
}

#define SHELL_INPUT_MAX 700

int main(int argc, char **argv) {
  if (argc != 2) {
    printf("Usage: %s binary > textfile\n", argv[0]);
    exit(EXIT_FAILURE);
  }

  FILE *f = fopen(argv[1], "rb");
  if (!f) {
    printf("Error while open %s\n", argv[1]);
    exit(EXIT_FAILURE);
  }

  unsigned char byte;

  const char *filename = argv[1];
  int line = 0, chout = 0;
  const char *newf = ">";
  const char *exst = ">>";

  fprintf(stdout, "cd /tmp;F=%s;true>$F;chmod +x $F\n", filename);

  while (fread(&byte, 1, sizeof(byte), f)) {
    if (chout == 0) {
      chout += fprintf(stdout, "printf \"");
      line++;
    }
    if (trtable[byte]) {
      chout += fprintf(stdout, "%s", trtable[byte]);
    } else {
      chout += fprintf(stdout, "\\x%.2X", byte);
    }
    if (chout > SHELL_INPUT_MAX) {
      fprintf(stdout, "\"%s%s\n", line == 1 ? newf : exst, "$F");
      chout = 0;
    }
  }
  if (chout) {
      fprintf(stdout, "\"%s%s\n", line == 1 ? newf : exst, "$F");
  }
  fprintf(stdout, "\n");

  fclose(f);
}
