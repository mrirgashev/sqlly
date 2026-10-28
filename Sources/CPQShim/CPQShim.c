#include "CPQShim.h"
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <poll.h>
#include <time.h>
#include <pthread.h>

typedef struct pg_conn PGconn;
typedef struct pg_result PGresult;
static void *library;
static pthread_mutex_t load_lock = PTHREAD_MUTEX_INITIALIZER;
static char load_error[1024] = "libpq has not been loaded";
#define DECLARE(R,N,A) static R (*p_##N) A
DECLARE(PGconn *,PQconnectdb,(const char *));
DECLARE(int,PQstatus,(const PGconn *));
DECLARE(char *,PQerrorMessage,(const PGconn *));
DECLARE(void,PQfinish,(PGconn *));
DECLARE(int,PQsendQuery,(PGconn *,const char *));
DECLARE(int,PQsetSingleRowMode,(PGconn *));
DECLARE(int,PQconsumeInput,(PGconn *));
DECLARE(int,PQisBusy,(PGconn *));
DECLARE(PGresult *,PQgetResult,(PGconn *));
DECLARE(int,PQresultStatus,(const PGresult *));
DECLARE(char *,PQresultErrorMessage,(const PGresult *));
DECLARE(char *,PQresultErrorField,(const PGresult *,int));
DECLARE(int,PQnfields,(const PGresult *));
DECLARE(int,PQntuples,(const PGresult *));
DECLARE(char *,PQfname,(const PGresult *,int));
DECLARE(uint32_t,PQftype,(const PGresult *,int));
DECLARE(char *,PQgetvalue,(const PGresult *,int,int));
DECLARE(int,PQgetisnull,(const PGresult *,int,int));
DECLARE(int,PQgetlength,(const PGresult *,int,int));
DECLARE(char *,PQcmdStatus,(PGresult *));
DECLARE(int,PQsocket,(const PGconn *));
DECLARE(void,PQclear,(PGresult *));

int qc_load_postgres(const char *path) {
    pthread_mutex_lock(&load_lock);
    if (library) { pthread_mutex_unlock(&load_lock); return 1; }
    library = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!library) { snprintf(load_error,sizeof(load_error),"%s",dlerror()); pthread_mutex_unlock(&load_lock); return 0; }
#define LOAD(N) do { *(void **)(&p_##N) = dlsym(library,#N); if (!p_##N) { snprintf(load_error,sizeof(load_error),"Missing libpq symbol: %s",#N); dlclose(library); library=NULL; pthread_mutex_unlock(&load_lock); return 0; } } while(0)
    LOAD(PQconnectdb); LOAD(PQstatus); LOAD(PQerrorMessage); LOAD(PQfinish); LOAD(PQsendQuery);
    LOAD(PQsetSingleRowMode); LOAD(PQconsumeInput); LOAD(PQisBusy); LOAD(PQgetResult);
    LOAD(PQresultStatus); LOAD(PQresultErrorMessage); LOAD(PQresultErrorField); LOAD(PQnfields);
    LOAD(PQntuples); LOAD(PQfname); LOAD(PQftype); LOAD(PQgetvalue); LOAD(PQgetisnull);
    LOAD(PQgetlength); LOAD(PQcmdStatus); LOAD(PQsocket); LOAD(PQclear);
#undef LOAD
    load_error[0]='\0'; pthread_mutex_unlock(&load_lock); return 1;
}
const char *qc_load_error(void) { return load_error; }
static double monotonic_time(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t);
    return (double)t.tv_sec + (double)t.tv_nsec/1000000000.0;
}
static void clear_table(QCResult *r) {
    for (int i=0;i<r->row_count;i++) { for (int j=0;j<r->column_count;j++) free(r->rows[i][j]); free(r->rows[i]); }
    free(r->rows); r->rows=NULL; r->row_count=0;
    for (int j=0;j<r->column_count;j++) free(r->column_names[j]);
    free(r->column_names); free(r->column_types); r->column_names=NULL; r->column_types=NULL; r->column_count=0;
}
void qc_free_result(QCResult *r) { if (!r) return; clear_table(r); free(r->error); free(r->sqlstate); free(r->command); free(r); }
static void fail(QCResult *r,const char *error,const char *state) {
    r->status=0; free(r->error); free(r->sqlstate);
    r->error=strdup(error ? error : "PostgreSQL operation failed"); r->sqlstate=strdup(state ? state : "");
}
static void columns(QCResult *r,PGresult *pg) {
    clear_table(r); r->column_count=p_PQnfields(pg);
    r->column_names=calloc((size_t)r->column_count,sizeof(char *));
    r->column_types=calloc((size_t)r->column_count,sizeof(uint32_t));
    for(int c=0;c<r->column_count;c++) { r->column_names[c]=strdup(p_PQfname(pg,c)); r->column_types[c]=p_PQftype(pg,c); }
}
QCResult *qc_execute(const char *connection,const char *sql,int timeout_ms,int max_rows,int max_bytes) {
    double began=monotonic_time();
    QCResult *r=calloc(1,sizeof(QCResult)); r->command=strdup(""); r->status=1;
    if (!library) { fail(r,load_error,""); return r; }
    PGconn *conn=p_PQconnectdb(connection);
    if (!conn || p_PQstatus(conn)!=0) { fail(r,conn ? p_PQerrorMessage(conn) : "Cannot allocate connection",""); if(conn)p_PQfinish(conn); return r; }
    if (!p_PQsendQuery(conn,sql)) { fail(r,p_PQerrorMessage(conn),""); p_PQfinish(conn); return r; }
    p_PQsetSingleRowMode(conn);
    int new_statement=1, bytes=0;
    for(;;) {
        if ((monotonic_time()-began)*1000.0 > timeout_ms) { fail(r,"Query exceeded the practice time limit. Simplify the query and run it again.","57014"); break; }
        if (!p_PQconsumeInput(conn)) { fail(r,p_PQerrorMessage(conn),""); break; }
        if(p_PQisBusy(conn)) { struct pollfd fd={p_PQsocket(conn),POLLIN,0}; poll(&fd,1,10); continue; }
        PGresult *pg=p_PQgetResult(conn); if(!pg) break;
        int status=p_PQresultStatus(pg);
        if(status==9 || status==2) {
            if(new_statement) { columns(r,pg); new_statement=0; bytes=0; }
            int nr=p_PQntuples(pg);
            for(int row=0;row<nr;row++) {
                if(r->row_count>=max_rows) { fail(r,"Result exceeds the 2,000-row practice limit. Add a filter or LIMIT.","54000"); break; }
                int row_bytes=0;
                for(int c=0;c<r->column_count;c++) row_bytes+=p_PQgetlength(pg,row,c);
                if(row_bytes>max_bytes || bytes>max_bytes-row_bytes) { fail(r,"Result exceeds the 4 MB practice limit. Select fewer values.","54000"); break; }
                bytes+=row_bytes;
                char ***grown=realloc(r->rows,(size_t)(r->row_count+1)*sizeof(char **));
                if(!grown) { fail(r,"Not enough memory for query results.","53200"); break; }
                r->rows=grown; char **values=calloc((size_t)r->column_count,sizeof(char *));
                for(int c=0;c<r->column_count;c++) if(!p_PQgetisnull(pg,row,c)) values[c]=strdup(p_PQgetvalue(pg,row,c));
                r->rows[r->row_count++]=values;
            }
            if(status==2) { free(r->command); r->command=strdup(p_PQcmdStatus(pg)); new_statement=1; }
        } else if(status==1 || status==0) {
            clear_table(r); free(r->command); r->command=strdup(p_PQcmdStatus(pg)); new_statement=1;
        } else if(status==3 || status==4 || status==8) {
            fail(r,"COPY streaming is unavailable in the practice editor. Use INSERT or SELECT instead.","0A000");
        } else {
            fail(r,p_PQresultErrorMessage(pg),p_PQresultErrorField(pg,'C'));
        }
        p_PQclear(pg); if(!r->status) break;
    }
    /* Closing an unfinished connection aborts its backend transaction. The actor
       additionally terminates the disposable database's backends during cleanup. */
    p_PQfinish(conn); r->duration=monotonic_time()-began; return r;
}
