#include <stdio.h>
#include <stdlib.h>

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

  unsigned char buf[100];
  int nlen;

  const char *filename = argv[1];
  int line = 0;
  const char *newf = ">";
  const char *exst = ">>";
  fprintf(stdout, "rm %s; while IFS= read -s -r line; do $line>>%s; done\n",
          filename, filename);

  while ((nlen = fread(buf, 1, sizeof(buf), f))) {
    line++;
    fprintf(stdout, "printf \"");
    for (int i = 0; i < nlen; i++) {
      fprintf(stdout, "\\x%02X", buf[i]);
    }
    //fprintf(stdout, "\"%s%s\n", line == 1 ? newf : exst, filename);
    fprintf(stdout, "\"\n");
  }
  fprintf(stdout, "\n\004\n\nchmod +x %s\n\n", filename);

  fclose(f);
}
