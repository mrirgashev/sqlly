#ifndef CPQSHIM_H
#define CPQSHIM_H
#include <stdint.h>
typedef struct {
    int status;
    char *error;
    char *sqlstate;
    int column_count;
    char **column_names;
    uint32_t *column_types;
    int row_count;
    char ***rows;
    char *command;
    double duration;
} QCResult;
int qc_load_postgres(const char *library_path);
const char *qc_load_error(void);
QCResult *qc_execute(const char *connection, const char *sql, int timeout_ms, int max_rows, int max_bytes);
void qc_free_result(QCResult *result);
#endif
