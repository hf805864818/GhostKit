//
//  SpawnBridge.c
//  GhostKit
//
//  C bridge for posix_spawn on iOS.
//  Swift blocks popen/system/process spawning, so we implement
//  the spawn logic in C and expose it to Swift.
//

#include "SpawnBridge.h"

int spawn_and_capture(const char *path,
                       char *const argv[],
                       char *output,
                       int out_size)
{
    int pipefd[2];
    if (pipe(pipefd) != 0) {
        return -1;
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipefd[0]);
    posix_spawn_file_actions_addclose(&actions, pipefd[1]);

    pid_t pid = 0;
    extern char **environ;
    int rc = posix_spawn(&pid, path, &actions, NULL, argv, environ);

    posix_spawn_file_actions_destroy(&actions);

    if (rc != 0) {
        close(pipefd[0]);
        close(pipefd[1]);
        return -1;
    }

    close(pipefd[1]);

    int total = 0;
    if (output && out_size > 0) {
        output[0] = '\0';
        ssize_t n;
        while ((n = read(pipefd[0], output + total, out_size - total - 1)) > 0) {
            total += (int)n;
            if (total >= out_size - 1) break;
        }
        output[total] = '\0';
    }

    close(pipefd[0]);

    int status = 0;
    waitpid(pid, &status, 0);

    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    return -2;
}

int spawn_simple(const char *path,
                  const char *args,
                  char *output,
                  int out_size)
{
    if (!path) return -1;

    /* Build argv array */
    char *argv[64];
    int argc = 0;

    argv[argc++] = strdup(path);

    if (args && *args) {
        char *args_copy = strdup(args);
        char *tok = strtok(args_copy, " \t");
        while (tok && argc < 63) {
            argv[argc++] = strdup(tok);
            tok = strtok(NULL, " \t");
        }
        free(args_copy);
    }
    argv[argc] = NULL;

    int result = spawn_and_capture(path, argv, output, out_size);

    /* Free argv */
    for (int i = 0; i < argc; i++) {
        free(argv[i]);
    }

    return result;
}
