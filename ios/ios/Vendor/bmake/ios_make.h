#ifndef IOS_MAKE_H
#define IOS_MAKE_H

typedef int (*ios_make_recipe_callback)(const char *command, void *context);

int ios_make_run(int argc, char **argv,
    ios_make_recipe_callback callback, void *context);
int ios_make_execute_recipe(const char *command);
void ios_make_exit(int status) __attribute__((noreturn));

#endif