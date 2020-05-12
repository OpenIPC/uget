#include <arpa/inet.h>
#include <netdb.h>
#include <stddef.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#define ERR_GENERAL 1
#define ERR_SOCKET 2
#define ERR_GETADDRINFO 3
#define ERR_CONNECT 4
#define ERR_SEND 5
#define ERR_USAGE 6
#define ERR_BADURL 7

#define NDEBUG

#ifndef NDEBUG
#include <stdio.h>
#endif

int download(int writefd, char *hostname, char *uri) {
  int ret = ERR_GENERAL;

  struct addrinfo hints, *res, *res0;

  memset(&hints, 0, sizeof(hints));
  hints.ai_family = PF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  int err = getaddrinfo(hostname, "http", &hints, &res0);
  if (err)
    return ERR_GETADDRINFO;

  int s = -1;
  for (res = res0; res; res = res->ai_next) {
    s = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (s < 0) {
      ret = ERR_SOCKET;
      continue;
    }

#ifndef NDEBUG
    char buf[256];
    inet_ntop(res->ai_family, &((struct sockaddr_in *)res->ai_addr)->sin_addr,
              buf, sizeof(buf));
    printf("Connect to %s\n", buf);
#endif

    if (connect(s, res->ai_addr, res->ai_addrlen) < 0) {
      ret = ERR_CONNECT;
      close(s);
      s = -1;
      continue;
    }
    break; /* okay we got one */
  }
  freeaddrinfo(res0);

  if (s < 0) {
    return ret;
  }

  char buf[4096] = "GET /";
  strncat(buf, uri, sizeof(buf) - strlen(buf) - 1);
  strncat(buf, " HTTP/1.0\r\nHost: ", sizeof(buf) - strlen(buf) - 1);
  strncat(buf, hostname, sizeof(buf) - strlen(buf) - 1);
  strncat(buf, "\r\n\r\n", sizeof(buf) - strlen(buf) - 1);
  int tosent = strlen(buf);
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

      header = 0;
      ptr+=4;
      nrecvd -= ptr - buf;
    }
    write(writefd, ptr, nrecvd);
  }

  return 0;
}

int main(int argc, char **argv) {
  if (argc < 2)
    return ERR_USAGE;

  char *url = argv[1];
  char *uri = NULL;
  while (*url) {
    if (*url == '/') {
      *url++ = 0;
      uri = url;
      break;
    }
    url++;
  }

  if (!uri)
    return ERR_BADURL;

  return download(1, argv[1], uri);
}
