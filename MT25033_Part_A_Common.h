/*
 * MT25033_Part_A_Common.h
 * Common header file for Network I/O Assignment
 * Roll Number: MT25033
 *
 * This header defines the Message structure with 8 dynamically allocated
 * string fields and common utility functions used by all implementations.
 */

#ifndef MT25033_PART_A_COMMON_H
#define MT25033_PART_A_COMMON_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>
#include <time.h>
#include <sys/time.h>

/* Default configuration values */
#define DEFAULT_PORT 8080
#define DEFAULT_MSG_SIZE 1024
#define DEFAULT_DURATION 10        /* seconds */
#define DEFAULT_NUM_THREADS 4
#define NUM_FIELDS 8               /* Number of string fields in Message */

/*
 * Message structure with 8 dynamically allocated string fields
 * Each field is heap-allocated using malloc()
 * This structure is used to demonstrate data copy overhead
 */
typedef struct {
    char *field1;
    char *field2;
    char *field3;
    char *field4;
    char *field5;
    char *field6;
    char *field7;
    char *field8;
} Message;

/*
 * Serialized message for network transfer
 * Contains the actual data bytes to be sent over the socket
 */
typedef struct {
    size_t total_size;             /* Total size of serialized data */
    size_t field_size;             /* Size of each field */
    char data[];                   /* Flexible array member for data */
} SerializedMessage;

/* Thread argument structure for server threads */
typedef struct {
    int client_fd;
    int thread_id;
    size_t msg_size;
    int duration;
    /* Metrics */
    unsigned long bytes_sent;
    unsigned long messages_sent;
    double elapsed_time;
} ServerThreadArgs;

/* Thread argument structure for client threads */
typedef struct {
    int thread_id;
    const char *server_ip;
    int server_port;
    size_t msg_size;
    int duration;
    /* Metrics */
    unsigned long bytes_received;
    unsigned long messages_received;
    double total_latency;
    double elapsed_time;
} ClientThreadArgs;

/* Global metrics structure */
typedef struct {
    unsigned long total_bytes;
    unsigned long total_messages;
    double total_time;
    double throughput_gbps;
    double avg_latency_us;
} Metrics;

/*
 * Allocate and initialize a Message structure
 * Each field is allocated with the specified size and filled with data
 */
static inline Message* create_message(size_t field_size) {
    Message *msg = (Message*)malloc(sizeof(Message));
    if (!msg) {
        perror("Failed to allocate Message");
        return NULL;
    }

    /* Allocate each field on the heap */
    msg->field1 = (char*)malloc(field_size);
    msg->field2 = (char*)malloc(field_size);
    msg->field3 = (char*)malloc(field_size);
    msg->field4 = (char*)malloc(field_size);
    msg->field5 = (char*)malloc(field_size);
    msg->field6 = (char*)malloc(field_size);
    msg->field7 = (char*)malloc(field_size);
    msg->field8 = (char*)malloc(field_size);

    /* Check allocations */
    if (!msg->field1 || !msg->field2 || !msg->field3 || !msg->field4 ||
        !msg->field5 || !msg->field6 || !msg->field7 || !msg->field8) {
        perror("Failed to allocate message fields");
        free(msg->field1); free(msg->field2); free(msg->field3); free(msg->field4);
        free(msg->field5); free(msg->field6); free(msg->field7); free(msg->field8);
        free(msg);
        return NULL;
    }

    /* Fill fields with pattern data */
    memset(msg->field1, 'A', field_size);
    memset(msg->field2, 'B', field_size);
    memset(msg->field3, 'C', field_size);
    memset(msg->field4, 'D', field_size);
    memset(msg->field5, 'E', field_size);
    memset(msg->field6, 'F', field_size);
    memset(msg->field7, 'G', field_size);
    memset(msg->field8, 'H', field_size);

    return msg;
}

/*
 * Free all memory associated with a Message
 */
static inline void free_message(Message *msg) {
    if (msg) {
        free(msg->field1);
        free(msg->field2);
        free(msg->field3);
        free(msg->field4);
        free(msg->field5);
        free(msg->field6);
        free(msg->field7);
        free(msg->field8);
        free(msg);
    }
}

/*
 * Serialize a Message into a contiguous buffer for sending
 * Returns a newly allocated SerializedMessage
 */
static inline SerializedMessage* serialize_message(Message *msg, size_t field_size) {
    size_t total_data_size = NUM_FIELDS * field_size;
    size_t total_size = sizeof(SerializedMessage) + total_data_size;

    SerializedMessage *smsg = (SerializedMessage*)malloc(total_size);
    if (!smsg) {
        perror("Failed to allocate SerializedMessage");
        return NULL;
    }

    smsg->total_size = total_data_size;
    smsg->field_size = field_size;

    /* Copy each field into the serialized buffer */
    char *ptr = smsg->data;
    memcpy(ptr, msg->field1, field_size); ptr += field_size;
    memcpy(ptr, msg->field2, field_size); ptr += field_size;
    memcpy(ptr, msg->field3, field_size); ptr += field_size;
    memcpy(ptr, msg->field4, field_size); ptr += field_size;
    memcpy(ptr, msg->field5, field_size); ptr += field_size;
    memcpy(ptr, msg->field6, field_size); ptr += field_size;
    memcpy(ptr, msg->field7, field_size); ptr += field_size;
    memcpy(ptr, msg->field8, field_size);

    return smsg;
}

/*
 * Get current time in microseconds
 */
static inline double get_time_us(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000000.0 + tv.tv_usec;
}

/*
 * Get current time in seconds (high precision)
 */
static inline double get_time_sec(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1000000000.0;
}

/*
 * Calculate throughput in Gbps
 */
static inline double calc_throughput_gbps(unsigned long bytes, double seconds) {
    if (seconds <= 0) return 0.0;
    return (bytes * 8.0) / (seconds * 1000000000.0);
}

/*
 * Print usage information
 */
static inline void print_usage(const char *prog_name, int is_server) {
    if (is_server) {
        printf("Usage: %s [options]\n", prog_name);
        printf("Options:\n");
        printf("  -p <port>      Port number (default: %d)\n", DEFAULT_PORT);
        printf("  -s <size>      Message field size in bytes (default: %d)\n", DEFAULT_MSG_SIZE);
        printf("  -d <duration>  Test duration in seconds (default: %d)\n", DEFAULT_DURATION);
        printf("  -h             Show this help\n");
    } else {
        printf("Usage: %s [options]\n", prog_name);
        printf("Options:\n");
        printf("  -i <ip>        Server IP address (default: 127.0.0.1)\n");
        printf("  -p <port>      Server port (default: %d)\n", DEFAULT_PORT);
        printf("  -s <size>      Message field size in bytes (default: %d)\n", DEFAULT_MSG_SIZE);
        printf("  -t <threads>   Number of client threads (default: %d)\n", DEFAULT_NUM_THREADS);
        printf("  -d <duration>  Test duration in seconds (default: %d)\n", DEFAULT_DURATION);
        printf("  -h             Show this help\n");
    }
}

#endif /* MT25033_PART_A_COMMON_H */
