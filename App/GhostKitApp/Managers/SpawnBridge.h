//
//  SpawnBridge.h
//  GhostKit
//
//  C bridge for posix_spawn - Swift blocks popen/system on iOS,
//  so we wrap posix_spawn in C and expose it to Swift via bridging header.
//

#ifndef SpawnBridge_h
#define SpawnBridge_h

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <spawn.h>
#include <sys/wait.h>

/// Spawn a binary at `path` with given arguments via posix_spawn.
/// Captures combined stdout+stderr into `output` buffer.
///
/// @param path     Full path to the executable binary.
/// @param argv     NULL-terminated array of C string arguments (argv[0] = path).
/// @param output   Buffer to receive captured output.
/// @param out_size Size of the output buffer.
/// @return Exit status of the spawned process, or -1 on failure.
int spawn_and_capture(const char *path,
                       char *const argv[],
                       char *output,
                       int out_size);

/// Convenience: spawn a binary with a simple argument string.
/// Splits `args` by spaces and passes as argv.
///
/// @param path     Full path to the executable.
/// @param args     Space-separated arguments (may be NULL).
/// @param output   Buffer for captured output.
/// @param out_size Size of output buffer.
/// @return Exit status, or -1 on failure.
int spawn_simple(const char *path,
                  const char *args,
                  char *output,
                  int out_size);

#endif /* SpawnBridge_h */
