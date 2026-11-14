#include "EXTERN.h"
#include "perl.h"
#include "ios_pseudofork.h"

#if defined(PERL_IOS) && defined(USE_ITHREADS) && defined(HAS_PSEUDOFORK)

#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

typedef struct {
    Perl_ios_pseudofork_child *child;
    PerlInterpreter *interp;
} Perl_ios_pseudofork_child_arg;

struct Perl_ios_pseudofork_child {
    Perl_ios_pseudofork_child *next;
    PerlInterpreter *parent;
    Pid_t parent_pid;
    Pid_t pid;
    pthread_t thread;
    int thread_set;
    int complete;
    int joining;
    int joined;
    int reaping;
    I32 exit_status;
    int exit_status_set;
    int status;
};

static pthread_mutex_t ios_pseudofork_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t ios_pseudofork_condition = PTHREAD_COND_INITIALIZER;
static Pid_t ios_pseudofork_next_pid = 2;
static Perl_ios_pseudofork_child *ios_pseudofork_children;
static pthread_once_t ios_pseudofork_pid_once = PTHREAD_ONCE_INIT;
static pthread_key_t ios_pseudofork_pid_key;

static int
ios_pseudofork_ignore_sigpipe(void)
{
    struct sigaction action;

    action.sa_handler = SIG_IGN;
    sigemptyset(&action.sa_mask);
    action.sa_flags = 0;
    return sigaction(SIGPIPE, &action, NULL);
}

static void
ios_pseudofork_free_pid(void *value)
{
    free(value);
}

static void
ios_pseudofork_make_pid_key(void)
{
    (void)pthread_key_create(&ios_pseudofork_pid_key,
                             ios_pseudofork_free_pid);
}

static Pid_t
ios_pseudofork_allocate_pid_locked(void)
{
    Pid_t id = ios_pseudofork_next_pid++;

    if (ios_pseudofork_next_pid <= 1)
        ios_pseudofork_next_pid = 2;
    if (id <= 1)
        id = ios_pseudofork_next_pid++;
    return -id;
}

static void
ios_pseudofork_wait_for_thread(
    Perl_ios_pseudofork_child *child)
{
    pthread_mutex_lock(&ios_pseudofork_mutex);
    while (!child->thread_set)
        (void)pthread_cond_wait(&ios_pseudofork_condition,
                                &ios_pseudofork_mutex);
    pthread_mutex_unlock(&ios_pseudofork_mutex);
}

static void *
ios_pseudofork_start_child(void *arg)
{
    Perl_ios_pseudofork_child_arg *child_arg =
        (Perl_ios_pseudofork_child_arg *)arg;
    Perl_ios_pseudofork_child *child = child_arg->child;
    PerlInterpreter *my_perl = child_arg->interp;
    int status = 0;
    I32 exit_status;
    int run_status;
    volatile int oldscope;

    free(child_arg);
    ios_pseudofork_wait_for_thread(child);
    PERL_SET_THX(my_perl);
    if (Perl_ios_pseudofork_set_current_pid(
            Perl_ios_pseudofork_child_pid(child)) == -1) {
        Perl_ios_pseudofork_child_complete(child, 1 << 8);
        perl_destruct(my_perl);
        perl_free(my_perl);
        return NULL;
    }
    {
        dSP;
        dTARGET;
        EXTEND(SP, 1);
        PUSHi(0);
        PUTBACK;
    }

    PL_op = PL_op ? PL_op->op_next : NULL;
    oldscope = PL_scopestack_ix;

restart:
    {
        dJMPENV;

        JMPENV_PUSH(run_status);
        switch (run_status) {
        case 0:
            CALLRUNOPS(aTHX);
            status = 0;
            break;
        case 2:
            if (Perl_ios_pseudofork_get_exit_status(&exit_status))
                status = (exit_status & 0xff) << 8;
            else
                status = STATUS_EXIT < 0 ? -1 : (STATUS_EXIT & 0xff) << 8;
            while (PL_scopestack_ix > oldscope)
                LEAVE;
            FREETMPS;
            PL_curstash = PL_defstash;
            if (PL_endav && !PL_minus_c) {
                PERL_SET_PHASE(PERL_PHASE_END);
                call_list(oldscope, PL_endav);
            }
            break;
        case 3:
            if (PL_restartop) {
                POPSTACK_TO(PL_mainstack);
                PL_op = PL_restartop;
                PL_restartop = NULL;
                JMPENV_POP;
                goto restart;
            }
            status = 1 << 8;
            break;
        default:
            status = run_status << 8;
            break;
        }
        JMPENV_POP;
    }

    /*
     * The cloned interpreter inherits the parent's optree.  Do not let
     * perl_destruct() free that inherited tree as if it owned it.
     */
    PL_main_root = (OP *)NULL;

    Perl_ios_pseudofork_join_all(aTHX_ my_perl);
    perl_destruct(my_perl);
    perl_free(my_perl);
    Perl_ios_pseudofork_clear_current_pid();
    Perl_ios_pseudofork_child_complete(child, status);
    return NULL;
}

Perl_ios_pseudofork_child *
Perl_ios_pseudofork_child_create(pTHX_ PerlInterpreter *parent,
                                  Pid_t parent_pid)
{
    Perl_ios_pseudofork_child *child;

    Newxz(child, 1, Perl_ios_pseudofork_child);
    if (child == NULL)
        return NULL;
    child->parent = parent;
    child->parent_pid = parent_pid;

    pthread_mutex_lock(&ios_pseudofork_mutex);
    child->pid = ios_pseudofork_allocate_pid_locked();
    child->next = ios_pseudofork_children;
    ios_pseudofork_children = child;
    pthread_mutex_unlock(&ios_pseudofork_mutex);

    return child;
}

void
Perl_ios_pseudofork_child_set_thread(
    Perl_ios_pseudofork_child *child, pthread_t thread)
{
    pthread_mutex_lock(&ios_pseudofork_mutex);
    child->thread = thread;
    child->thread_set = TRUE;
    pthread_cond_broadcast(&ios_pseudofork_condition);
    pthread_mutex_unlock(&ios_pseudofork_mutex);
}

void
Perl_ios_pseudofork_child_complete(
    Perl_ios_pseudofork_child *child, int status)
{
    pthread_mutex_lock(&ios_pseudofork_mutex);
    child->status = status;
    child->complete = TRUE;
    pthread_cond_broadcast(&ios_pseudofork_condition);
    pthread_mutex_unlock(&ios_pseudofork_mutex);
}

Pid_t
Perl_ios_pseudofork_child_pid(
    const Perl_ios_pseudofork_child *child)
{
    return child->pid;
}

Pid_t
Perl_ios_pseudofork_child_parent_pid(
    const Perl_ios_pseudofork_child *child)
{
    return child->parent_pid;
}

PerlInterpreter *
Perl_ios_pseudofork_child_parent(
    const Perl_ios_pseudofork_child *child)
{
    return child->parent;
}

pthread_t
Perl_ios_pseudofork_child_thread(
    const Perl_ios_pseudofork_child *child)
{
    return child->thread;
}

int
Perl_ios_pseudofork_child_is_complete(
    const Perl_ios_pseudofork_child *child)
{
    int complete;

    pthread_mutex_lock(&ios_pseudofork_mutex);
    complete = child->complete;
    pthread_mutex_unlock(&ios_pseudofork_mutex);
    return complete;
}

int
Perl_ios_pseudofork_child_status(
    const Perl_ios_pseudofork_child *child)
{
    int status;

    pthread_mutex_lock(&ios_pseudofork_mutex);
    status = child->status;
    pthread_mutex_unlock(&ios_pseudofork_mutex);
    return status;
}

static Perl_ios_pseudofork_child *
ios_pseudofork_find_child_locked(PerlInterpreter *parent,
                                  Pid_t pid)
{
    Perl_ios_pseudofork_child *child = ios_pseudofork_children;

    while (child != NULL) {
        if (child->parent == parent && (pid == -1 || child->pid == pid))
            return child;
        child = child->next;
    }
    return NULL;
}

static Perl_ios_pseudofork_child *
ios_pseudofork_find_completed_child_locked(PerlInterpreter *parent,
                                           Pid_t pid)
{
    Perl_ios_pseudofork_child *child = ios_pseudofork_children;

    while (child != NULL) {
        if (child->parent == parent
            && (pid == -1 || child->pid == pid)
            && child->complete && !child->reaping)
            return child;
        child = child->next;
    }
    return NULL;
}

Pid_t
Perl_ios_pseudofork_wait(pTHX_ Pid_t pid, int *statusp, int flags)
{
    Perl_ios_pseudofork_child *child;
    Pid_t child_pid;
    int result;
    int status;

    if (pid >= 0) {
        errno = ECHILD;
        return -1;
    }

    pthread_mutex_lock(&ios_pseudofork_mutex);
    if (ios_pseudofork_find_child_locked(aTHX_ pid) == NULL) {
        pthread_mutex_unlock(&ios_pseudofork_mutex);
        errno = ECHILD;
        return -1;
    }
    for (;;) {
        child = ios_pseudofork_find_completed_child_locked(aTHX_ pid);
        if (child != NULL)
            break;
        if (ios_pseudofork_find_child_locked(aTHX_ pid) == NULL) {
            pthread_mutex_unlock(&ios_pseudofork_mutex);
            errno = ECHILD;
            return -1;
        }
        if (flags & WNOHANG) {
            pthread_mutex_unlock(&ios_pseudofork_mutex);
            return 0;
        }
        result = pthread_cond_wait(&ios_pseudofork_condition,
                                   &ios_pseudofork_mutex);
        if (result != 0) {
            pthread_mutex_unlock(&ios_pseudofork_mutex);
            errno = result;
            return -1;
        }
    }
    child->reaping = TRUE;
    status = child->status;
    pthread_mutex_unlock(&ios_pseudofork_mutex);

    if (Perl_ios_pseudofork_child_join(child) == -1) {
        pthread_mutex_lock(&ios_pseudofork_mutex);
        child->reaping = FALSE;
        pthread_cond_broadcast(&ios_pseudofork_condition);
        pthread_mutex_unlock(&ios_pseudofork_mutex);
        return -1;
    }
    if (statusp != NULL)
        *statusp = status;
    child_pid = child->pid;
    Perl_ios_pseudofork_child_reap(aTHX_ child);
    return child_pid;
}

Pid_t
Perl_ios_pseudofork_fork(pTHX)
{
    PerlInterpreter *parent = aTHX;
    Perl_ios_pseudofork_child *child;
    Perl_ios_pseudofork_child_arg *child_arg;
    PerlInterpreter *interp;
    pthread_t thread;
    int result;
    Pid_t parent_pid;

    /*
     * Pseudofork children share the native process, so SIGPIPE cannot be
     * isolated to one child. Convert broken-pipe writes into EPIPE instead
     * of allowing one interpreter to terminate the entire runner.
     */
    if (ios_pseudofork_ignore_sigpipe() == -1)
        return -1;

    parent_pid = Perl_ios_pseudofork_getpid();
    interp = perl_clone(parent, CLONEf_COPY_STACKS | CLONEf_CLONE_HOST);
    if (interp == NULL) {
        errno = ENOMEM;
        return -1;
    }
    PERL_SET_THX(parent);

    child = Perl_ios_pseudofork_child_create(aTHX_ parent, parent_pid);
    child_arg = (Perl_ios_pseudofork_child_arg *)
        malloc(sizeof(*child_arg));
    if (child == NULL || child_arg == NULL) {
        if (child_arg != NULL)
            free(child_arg);
        if (child != NULL)
            Perl_ios_pseudofork_child_reap(aTHX_ child);
        perl_destruct(interp);
        perl_free(interp);
        errno = ENOMEM;
        return -1;
    }
    child_arg->child = child;
    child_arg->interp = interp;

    result = pthread_create(&thread, NULL, ios_pseudofork_start_child,
                            child_arg);
    if (result != 0) {
        free(child_arg);
        Perl_ios_pseudofork_child_reap(aTHX_ child);
        perl_destruct(interp);
        perl_free(interp);
        errno = result;
        return -1;
    }
    Perl_ios_pseudofork_child_set_thread(child, thread);
    return Perl_ios_pseudofork_child_pid(child);
}

int
Perl_ios_pseudofork_child_join(
    Perl_ios_pseudofork_child *child)
{
    pthread_t thread;
    int result;

    pthread_mutex_lock(&ios_pseudofork_mutex);
    while (child->joining && !child->joined)
        pthread_cond_wait(&ios_pseudofork_condition, &ios_pseudofork_mutex);
    if (!child->thread_set || child->joined) {
        pthread_mutex_unlock(&ios_pseudofork_mutex);
        return 0;
    }
    thread = child->thread;
    if (pthread_equal(pthread_self(), thread)) {
        pthread_mutex_unlock(&ios_pseudofork_mutex);
        errno = EDEADLK;
        return -1;
    }
    child->joining = TRUE;
    pthread_mutex_unlock(&ios_pseudofork_mutex);

    result = pthread_join(thread, NULL);
    if (result != 0) {
        pthread_mutex_lock(&ios_pseudofork_mutex);
        child->joining = FALSE;
        pthread_cond_broadcast(&ios_pseudofork_condition);
        pthread_mutex_unlock(&ios_pseudofork_mutex);
        errno = result;
        return -1;
    }
    pthread_mutex_lock(&ios_pseudofork_mutex);
    child->joining = FALSE;
    child->joined = TRUE;
    pthread_cond_broadcast(&ios_pseudofork_condition);
    pthread_mutex_unlock(&ios_pseudofork_mutex);
    return 0;
}

void
Perl_ios_pseudofork_child_reap(
    pTHX_ Perl_ios_pseudofork_child *child)
{
    Perl_ios_pseudofork_child **link;

    pthread_mutex_lock(&ios_pseudofork_mutex);
    link = &ios_pseudofork_children;
    while (*link != NULL && *link != child)
        link = &(*link)->next;
    if (*link == child)
        *link = child->next;
    pthread_mutex_unlock(&ios_pseudofork_mutex);

    Safefree(child);
}

Pid_t
Perl_ios_pseudofork_getpid(void)
{
    Pid_t *pid;

    (void)pthread_once(&ios_pseudofork_pid_once,
                       ios_pseudofork_make_pid_key);
    pid = (Pid_t *)pthread_getspecific(ios_pseudofork_pid_key);
    return pid != NULL && *pid != 0 ? *pid : (Pid_t)getpid();
}

int
Perl_ios_pseudofork_set_current_pid(Pid_t pid)
{
    Pid_t *value;
    Pid_t *old_value;
    int result;

    (void)pthread_once(&ios_pseudofork_pid_once,
                       ios_pseudofork_make_pid_key);
    value = (Pid_t *)malloc(sizeof(*value));
    if (value == NULL) {
        errno = ENOMEM;
        return -1;
    }
    *value = pid;
    old_value = (Pid_t *)pthread_getspecific(ios_pseudofork_pid_key);
    result = pthread_setspecific(ios_pseudofork_pid_key, value);
    if (result != 0) {
        free(value);
        errno = result;
        return -1;
    }
    free(old_value);
    return 0;
}

void
Perl_ios_pseudofork_clear_current_pid(void)
{
    Pid_t *value;

    (void)pthread_once(&ios_pseudofork_pid_once,
                       ios_pseudofork_make_pid_key);
    value = (Pid_t *)pthread_getspecific(ios_pseudofork_pid_key);
    (void)pthread_setspecific(ios_pseudofork_pid_key, NULL);
    free(value);
}

void
Perl_ios_pseudofork_record_exit_status(I32 status)
{
    Perl_ios_pseudofork_child *child;
    Pid_t pid;

    pid = Perl_ios_pseudofork_getpid();
    pthread_mutex_lock(&ios_pseudofork_mutex);
    child = ios_pseudofork_children;
    while (child != NULL && child->pid != pid)
        child = child->next;
    if (child != NULL) {
        child->exit_status = status;
        child->exit_status_set = TRUE;
    }
    pthread_mutex_unlock(&ios_pseudofork_mutex);
}

int
Perl_ios_pseudofork_get_exit_status(I32 *statusp)
{
    Perl_ios_pseudofork_child *child;
    int result;
    Pid_t pid;

    pid = Perl_ios_pseudofork_getpid();
    pthread_mutex_lock(&ios_pseudofork_mutex);
    child = ios_pseudofork_children;
    while (child != NULL && child->pid != pid)
        child = child->next;
    result = child != NULL && child->exit_status_set;
    if (result && statusp != NULL)
        *statusp = child->exit_status;
    pthread_mutex_unlock(&ios_pseudofork_mutex);
    if (result) {
        return TRUE;
    }
    return FALSE;
}

int
Perl_ios_pseudofork_kill(pTHX_ Pid_t pid, int sig)
{
    Perl_ios_pseudofork_child *child;
    pthread_t thread;
    int result;

    pthread_mutex_lock(&ios_pseudofork_mutex);
    child = ios_pseudofork_find_child_locked(aTHX_ pid);
    if (child == NULL || !child->thread_set) {
        pthread_mutex_unlock(&ios_pseudofork_mutex);
        errno = ESRCH;
        return -1;
    }
    thread = child->thread;
    pthread_mutex_unlock(&ios_pseudofork_mutex);

    result = pthread_kill(thread, sig);
    if (result != 0) {
        errno = result;
        return -1;
    }
    return 0;
}

void
Perl_ios_pseudofork_join_all(pTHX_ PerlInterpreter *parent)
{
    Perl_ios_pseudofork_child *child;

    for (;;) {
        pthread_mutex_lock(&ios_pseudofork_mutex);
        child = ios_pseudofork_children;
        while (child != NULL
               && (child->parent != parent || child->reaping))
            child = child->next;
        if (child != NULL)
            child->reaping = TRUE;
        pthread_mutex_unlock(&ios_pseudofork_mutex);

        if (child == NULL)
            return;
        if (Perl_ios_pseudofork_child_join(child) == -1) {
            pthread_mutex_lock(&ios_pseudofork_mutex);
            child->reaping = FALSE;
            pthread_cond_broadcast(&ios_pseudofork_condition);
            pthread_mutex_unlock(&ios_pseudofork_mutex);
            return;
        }
        Perl_ios_pseudofork_child_reap(aTHX_ child);
    }
}

#endif /* PERL_IOS && USE_ITHREADS && HAS_PSEUDOFORK */
