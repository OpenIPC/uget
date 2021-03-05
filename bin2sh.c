#include <stdio.h>
#include <stdlib.h>
#include <string.h>

const char *trtable[256] = {
    "\\0", // 0
    NULL,  // 1
    NULL,  // 2
    NULL,  // 3
    NULL,  // 4
    NULL,  // 5
    NULL,  // 6
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
  int printf_mode = 1;
  const char *input = NULL;

  if (argc == 3) {
    // treat first argument as optional key
    if (!strcmp(argv[1], "-echo")) {
      printf_mode = 0;
      input = argv[2];
    }
  } else if (argc == 2) {
    input = argv[1];
  }
  if (!input) {
    printf("Usage: %s [-echo] binary > textfile\n", argv[0]);
    exit(EXIT_FAILURE);
  }

  FILE *f = fopen(input, "rb");
  if (!f) {
    printf("Error while open %s\n", input);
    exit(EXIT_FAILURE);
  }

  unsigned char byte;

  int line = 0, chout = 0;
  const char *newf = ">";
  const char *exst = ">>";
  const char *echo_ = "echo -ne \"";
  const char *printf_ = "printf \"";

  fprintf(stdout, "cd /tmp;F=%s;true>$F;chmod +x $F\n", input);

  while (fread(&byte, 1, sizeof(byte), f)) {
    if (chout == 0) {
      chout += fprintf(stdout, "%s", printf_mode ? printf_ : echo_);
      line++;
    }
    if (byte == '"')
      chout += fprintf(stdout, "\"");
    else if (trtable[byte])
      chout += fprintf(stdout, "%s", trtable[byte]);
    else
      chout += fprintf(stdout, "\\x%X", byte);
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
