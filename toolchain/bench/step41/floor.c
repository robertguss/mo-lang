/* The floor for step 41's numbers: the same runs as runs.mo, from C with posix_spawn, the child's
 * stdout a pipe read to its end (and stderr a pipe for `true`, as Mo's are), then waitpid.
 *
 *     cc -O2 -o floor floor.c && ./floor MODE N
 */
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static int one(char *const argv[], size_t want) {
    int out[2], err[2];
    if (pipe(out) != 0 || pipe(err) != 0) return 0;
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, out[1], 1);
    posix_spawn_file_actions_adddup2(&fa, err[1], 2);
    posix_spawn_file_actions_addclose(&fa, out[0]);
    posix_spawn_file_actions_addclose(&fa, err[0]);
    char *const envp[] = {NULL};
    pid_t pid;
    int rc = posix_spawn(&pid, argv[0], &fa, NULL, argv, envp);
    posix_spawn_file_actions_destroy(&fa);
    close(out[1]);
    close(err[1]);
    if (rc != 0) return 0;
    static char buf[1 << 16];
    size_t got = 0;
    ssize_t n;
    while ((n = read(out[0], buf, sizeof buf)) > 0) got += (size_t)n;
    while ((n = read(err[0], buf, sizeof buf)) > 0) {
    }
    close(out[0]);
    close(err[0]);
    int status;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) && WEXITSTATUS(status) == 0 && got == want;
}

int main(int argc, char **argv) {
    const char *mode = argc > 1 ? argv[1] : "";
    long n = argc > 2 ? atol(argv[2]) : 0;
    char *truth[] = {"/usr/bin/true", NULL};
    char *mib[] = {"/usr/bin/head", "-c", "1048576", "/dev/zero", NULL};
    long done = 0;
    for (long i = 0; i < n; i++) done += strcmp(mode, "true") == 0 ? one(truth, 0) : one(mib, 1048576);
    printf("%ld of %ld\n", done, n);
    return 0;
}
