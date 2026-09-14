/* jobq load: create JOBS jobs on a queue, then WORKERS threads lease and ack for SECONDS, one
 * connection per request (jobq answers connection: close). Prints lease-and-ack pairs a second.
 * usage: jqload PORT WORKERS SECONDS JOBS [CROWD]  (CROWD silent connections held open meanwhile) */
#include <arpa/inet.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

static int port;
static atomic_long pairs, empty, errors;
static atomic_int stop;
/* leaseonly: lease with a short lease and never ack, so the leases run out (the requeue question). */
static int lease_only;
static char lease_body[64] = "{\"lease_ms\": 60000}";

static double now_s(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }

static int connect_local(void) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in a = {0};
    a.sin_family = AF_INET;
    a.sin_port = htons((uint16_t)port);
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (connect(fd, (struct sockaddr *)&a, sizeof a) != 0) { close(fd); return -1; }
    return fd;
}

/* One request; the response's status, and its body in `body` (NUL-terminated). */
static int request(const char *method, const char *path, const char *token, const char *json, char *body, size_t cap) {
    int fd = connect_local();
    if (fd < 0) return -1;
    char req[1024];
    int n = snprintf(req, sizeof req, "%s %s HTTP/1.1\r\nhost: 127.0.0.1\r\nauthorization: Bearer %s\r\ncontent-length: %zu\r\n\r\n%s", method, path, token, strlen(json), json);
    if (write(fd, req, (size_t)n) != n) { close(fd); return -1; }
    char buf[65536];
    size_t got = 0;
    for (;;) {
        ssize_t r = read(fd, buf + got, sizeof buf - 1 - got);
        if (r <= 0) break;
        got += (size_t)r;
        if (got == sizeof buf - 1) break;
    }
    close(fd);
    buf[got] = 0;
    int status = 0;
    if (sscanf(buf, "HTTP/1.1 %d", &status) != 1) return -1;
    char *b = strstr(buf, "\r\n\r\n");
    if (body) { snprintf(body, cap, "%s", b ? b + 4 : ""); }
    return status;
}

static void *worker(void *arg) {
    char token[32];
    snprintf(token, sizeof token, "w%ld", (long)(intptr_t)arg);
    char body[8192], path[128];
    while (!atomic_load(&stop)) {
        int s = request("POST", "/queues/load/lease", token, lease_body, body, sizeof body);
        if (s != 200) { if (s == 204 || s == 404) atomic_fetch_add(&empty, 1); else atomic_fetch_add(&errors, 1); continue; }
        char *id = strstr(body, "\"id\": \"");
        if (!id) { atomic_fetch_add(&errors, 1); continue; }
        if (lease_only) { atomic_fetch_add(&pairs, 1); continue; }
        id += 7;
        char *end = strchr(id, '"');
        if (!end) { atomic_fetch_add(&errors, 1); continue; }
        snprintf(path, sizeof path, "/jobs/%.*s/ack", (int)(end - id), id);
        s = request("POST", path, token, "", NULL, 0);
        if (s == 200) atomic_fetch_add(&pairs, 1); else atomic_fetch_add(&errors, 1);
    }
    return NULL;
}

static void *creator(void *arg) {
    long n = (long)(intptr_t)arg;
    for (long i = 0; i < n; i++) request("POST", "/jobs", "producer", "{\"queue\": \"load\", \"payload\": \"x\", \"max_attempts\": 3}", NULL, 0);
    return NULL;
}

int main(int argc, char **argv) {
    if (argc < 5) { fprintf(stderr, "usage: jqload PORT WORKERS SECONDS JOBS [CROWD]\n"); return 2; }
    port = atoi(argv[1]);
    int workers = atoi(argv[2]);
    double seconds = atof(argv[3]);
    long jobs = atol(argv[4]);
    int crowd = argc > 5 ? atoi(argv[5]) : 0;
    if (argc > 6 && strcmp(argv[6], "leaseonly") == 0) {
        lease_only = 1;
        snprintf(lease_body, sizeof lease_body, "{\"lease_ms\": 100}");
    }
    double t0 = now_s();
    pthread_t cs[8];
    for (int i = 0; i < 8; i++) pthread_create(&cs[i], NULL, creator, (void *)(intptr_t)(jobs / 8));
    for (int i = 0; i < 8; i++) pthread_join(cs[i], NULL);
    fprintf(stderr, "created %ld jobs in %.2f s\n", jobs / 8 * 8, now_s() - t0);
    int *silent = calloc((size_t)(crowd ? crowd : 1), sizeof(int));
    for (int i = 0; i < crowd; i++) silent[i] = connect_local();
    if (crowd) fprintf(stderr, "holding %d silent connections\n", crowd);
    pthread_t *ts = calloc((size_t)workers, sizeof(pthread_t));
    double start = now_s();
    for (int i = 0; i < workers; i++) pthread_create(&ts[i], NULL, worker, (void *)(intptr_t)i);
    while (now_s() - start < seconds) usleep(20000);
    atomic_store(&stop, 1);
    for (int i = 0; i < workers; i++) pthread_join(ts[i], NULL);
    double took = now_s() - start;
    for (int i = 0; i < crowd; i++) if (silent[i] >= 0) close(silent[i]);
    printf("workers %d seconds %.2f pairs %ld pairs_per_s %.0f empty %ld errors %ld\n", workers, took, atomic_load(&pairs), atomic_load(&pairs) / took, atomic_load(&empty), atomic_load(&errors));
    return 0;
}
