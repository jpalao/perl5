#ifndef PERL_IOS_PSEUDOFORK_H
#define PERL_IOS_PSEUDOFORK_H

#include "perl.h"

#if defined(PERL_IOS) && defined(USE_ITHREADS)

#include <pthread.h>

typedef struct Perl_ios_pseudofork_child Perl_ios_pseudofork_child;

Perl_ios_pseudofork_child *
Perl_ios_pseudofork_child_create(pTHX_ PerlInterpreter *parent,
                                  Pid_t parent_pid);

void
Perl_ios_pseudofork_child_set_thread(
    Perl_ios_pseudofork_child *child, pthread_t thread);

void
Perl_ios_pseudofork_child_complete(
    Perl_ios_pseudofork_child *child, int status);

Pid_t
Perl_ios_pseudofork_child_pid(
    const Perl_ios_pseudofork_child *child);

Pid_t
Perl_ios_pseudofork_child_parent_pid(
    const Perl_ios_pseudofork_child *child);

PerlInterpreter *
Perl_ios_pseudofork_child_parent(
    const Perl_ios_pseudofork_child *child);

pthread_t
Perl_ios_pseudofork_child_thread(
    const Perl_ios_pseudofork_child *child);

int
Perl_ios_pseudofork_child_is_complete(
    const Perl_ios_pseudofork_child *child);

int
Perl_ios_pseudofork_child_status(
    const Perl_ios_pseudofork_child *child);

int
Perl_ios_pseudofork_child_join(
    Perl_ios_pseudofork_child *child);

void
Perl_ios_pseudofork_child_reap(
    pTHX_ Perl_ios_pseudofork_child *child);

Pid_t
Perl_ios_pseudofork_getpid(void);

Pid_t
Perl_ios_pseudofork_fork(pTHX);

Pid_t
Perl_ios_pseudofork_wait(pTHX_ Pid_t pid, int *statusp, int flags);

int
Perl_ios_pseudofork_set_current_pid(Pid_t pid);

void
Perl_ios_pseudofork_clear_current_pid(void);

void
Perl_ios_pseudofork_join_all(pTHX_ PerlInterpreter *parent);

#endif /* PERL_IOS && USE_ITHREADS */

#endif /* PERL_IOS_PSEUDOFORK_H */
