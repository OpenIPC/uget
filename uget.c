#include <stdlib.h>
#include <string.h>

#include <arpa/inet.h>
#include <netdb.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define ERR_GENERAL 1
#define ERR_SOCKET 2
#define ERR_GETADDRINFO 3
#define ERR_CONNECT 4
#define ERR_SEND 5
#define ERR_USAGE 6

int get_http_respcode(const char *buf) {
  int i, code = 0;
  while (*buf && *buf != ' ') buf++;
  while (*buf == ' ') buf++;
  for (i = 0; i < 3 && *buf >= '0' && *buf <= '9'; i++)
    code = code * 10 + (*buf++ - '0');
  return code ? code : -1;
}

static char *bufcat(char *dst, const char *src) {
  while (*src) *dst++ = *src++;
  return dst;
}

int download(int writefd, char *hostname, char *uri) {
  struct hostent *he = gethostbyname(hostname);
  if (!he)
    return ERR_GETADDRINFO;

  int s = socket(AF_INET, SOCK_STREAM, 0);
  if (s < 0)
    return ERR_SOCKET;

  struct sockaddr_in addr;
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_port = htons(80);
  memcpy(&addr.sin_addr, he->h_addr, he->h_length);

  if (connect(s, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
    close(s);
    return ERR_CONNECT;
  }

  char buf[4096];
  char *p = bufcat(buf, "GET /");
  if (uri)
    p = bufcat(p, uri);
  p = bufcat(p, " HTTP/1.0\r\nHost: ");
  p = bufcat(p, hostname);
  p = bufcat(p, "\r\n\r\n");
  int tosent = p - buf;
  int nsent = send(s, buf, tosent, 0);
  if (nsent != tosent)
    return ERR_SEND;

  int header = 1;
  int nrecvd;
  while ((nrecvd = recv(s, buf, sizeof(buf), 0))) {
    char *ptr = buf;
    if (header) {
      ptr = strstr(buf, "\r\n\r\n");
      if (!ptr)
        continue;

      int rcode = get_http_respcode(buf);
      if (rcode / 100 != 2)
        return rcode / 100 * 10 + rcode % 10;

      header = 0;
      ptr += 4;
      nrecvd -= ptr - buf;
    }
    write(writefd, ptr, nrecvd);
  }

  return 0;
}

int main(int argc, char **argv) {
  if (argc < 2)
    return ERR_USAGE;

  int url_arg = 1;
  int run_program = 0;
  if (argc == 3) {
    if (strcmp("run", argv[1]) != 0)
      return ERR_USAGE;
    run_program = 1;
    url_arg++;
  }

  char *hostname = argv[url_arg];
  char *uri = NULL;

  char *url = hostname;
  while (*url) {
    if (*url == '/') {
      *url++ = 0;
      uri = url;
      break;
    }
    url++;
  }

  int fd = STDOUT_FILENO;
  char temfname[] = "/tmp/ugetXXXXXX";
  if (run_program) {
    fd = mkstemp(temfname);
  }

  int ret = download(fd, hostname, uri);
  if (ret)
    goto cleanup;

  if (run_program) {
    fchmod(fd, S_IRUSR | S_IXUSR);
    close(fd);
    int child = fork();
    if (child) {
      int wstatus;

      wait(&wstatus);
      ret = WEXITSTATUS(wstatus);
    } else {
      execl(temfname, temfname, (char *)NULL);
      return EXIT_FAILURE;
    }
  }

cleanup:
  if (run_program)
    unlink(temfname);

  return ret;
}
