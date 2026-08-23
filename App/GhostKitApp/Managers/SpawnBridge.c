//
//  SpawnBridge.c
//  GhostKit
//
//  C bridge for posix_spawn on iOS.
//  Swift blocks popen/system/process spawning, so we implement
//  the spawn logic in C and expose it to Swift.
//

#include "SpawnBridge.h"
#include <errno.h>
#include <sys/stat.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <spawn.h>
#include <sys/wait.h>

int spawn_and_capture(const char *path,
                       char *const argv[],
                       char *output,
                       int out_size)
{
    /* Clear output buffer */
    if (output && out_size > 0) {
        output[0] = '\0';
    }

    /* Verify the binary exists and is executable */
    struct stat st;
    if (stat(path, &st) != 0) {
        if (output && out_size > 0) {
            snprintf(output, out_size, "Binary not found: %s (errno=%d: %s)",
                     path, errno, strerror(errno));
        }
        return -1;
    }

    if (!S_ISREG(st.st_mode)) {
        if (output && out_size > 0) {
            snprintf(output, out_size, "Not a regular file: %s", path);
        }
        return -1;
    }

    /* Check execute permission */
    if (!(st.st_mode & S_IXUSR)) {
        /* Try to fix permissions */
        if (chmod(path, st.st_mode | 0755) != 0) {
            if (output && out_size > 0) {
                snprintf(output, out_size, "Cannot chmod +x: %s (errno=%d: %s)",
                         path, errno, strerror(errno));
            }
            return -1;
        }
    }

    int pipefd[2];
    if (pipe(pipefd) != 0) {
        if (output && out_size > 0) {
            snprintf(output, out_size, "pipe() failed: errno=%d: %s",
                     errno, strerror(errno));
        }
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
    
    /* Try to spawn with POSIX spawn attributes for better control */
    posix_spawnattr_t attrs;
    posix_spawnattr_init(&attrs);
    
    /* Set standard flags: no special flags needed */
    short flags = 0;
    posix_spawnattr_setflags(&attrs, flags);
    
    int rc = posix_spawn(&pid, path, &actions, &attrs, argv, environ);
    posix_spawnattr_destroy(&attrs);
    posix_spawn_file_actions_destroy(&actions);

    if (rc != 0) {
        close(pipefd[0]);
        close(pipefd[1]);
        /* Return the actual errno as a negative number for diagnosis.
         * Common codes:
         *   -1  = ENOENT (file not found)
         *   -2  = EAGAIN (resource temporarily unavailable)
         *   -13 = EACCES (permission denied)
         *   -22 = EINVAL (invalid argument)
         *   -86 = EBADARCH (wrong architecture)
         *   -88 = ENOEXEC (not executable / bad magic)
         */
        if (output && out_size > 0) {
            snprintf(output, out_size,
                     "posix_spawn('%s') failed: errno=%d (%s). "
                     "File mode=0%o size=%lld bytes. "
                     "Common causes: binary not found, wrong architecture, or sandbox denied access.",
                     path, rc, strerror(rc),
                     (unsigned)st.st_mode, (long long)st.st_size);
        }
        return -rc;  /* Negative errno for diagnosis */
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
    if (WIFSIGNALED(status)) {
        int sig = WTERMSIG(status);
        if (output && out_size > 0) {
            /* Append signal info after any captured output */
            int remaining = out_size - total - 1;
            if (remaining > 0) {
                if (total > 0) {
                    output[total++] = '\n';
                    remaining--;
                }
                snprintf(output + total, remaining,
                         "[RootHelper killed by signal %d (%s)]",
                         sig, strsignal(sig));
            }
        }
        return -256 - sig;
    }
    if (output && out_size > 0) {
        int remaining = out_size - total - 1;
        if (remaining > 0) {
            snprintf(output + total, remaining,
                     "[RootHelper terminated abnormally (status=0x%x)]", status);
        }
    }
    return -300;
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

/* ---------------------------------------------------------------------------
 * Persona spawn support for iOS 17+.
 *
 * This function attempts to spawn a process with elevated privileges.
 * On TrollStore, the RootHelper binary itself performs setuid(0) internally.
 * We use this wrapper to provide a clean interface.
 * --------------------------------------------------------------------------- */

int spawn_elevated(const char *path,
                   char *const argv[],
                   char *output,
                   int out_size)
{
    /* For now, fall back to regular spawn.
     * The RootHelper binary handles privilege escalation internally.
     */
    return spawn_and_capture(path, argv, output, out_size);
}
