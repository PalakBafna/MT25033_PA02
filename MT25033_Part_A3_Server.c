/*
 * MT25033_Part_A3_Server.c
 * Zero-Copy Server Implementation using MSG_ZEROCOPY
 * Roll Number: MT25033
 *
 * This implementation uses sendmsg() with MSG_ZEROCOPY flag to achieve
 * zero-copy transmission where data is sent directly from user-space
 * buffers without kernel copying.
 *
 * ZERO-COPY EXPLANATION:
 * With MSG_ZEROCOPY:
 * 1. The kernel pins user-space pages in memory
 * 2. The NIC DMAs directly from user-space buffer
 * 3. No copies occur between user and kernel space
 * 4. Application must wait for completion notification before reusing buffer
 *
 * KERNEL BEHAVIOR:
 * - setsockopt(SO_ZEROCOPY) enables the feature on the socket
 * - sendmsg() with MSG_ZEROCOPY returns immediately
 * - Kernel sends completion notification via error queue
 * - Application must poll error queue to know when buffer can be reused
 *
 * Requirements:
 * - Linux kernel 4.14+ for TCP zero-copy
 * - Root privileges or CAP_NET_ADMIN capability may be needed
 *
 * NOTE: If MSG_ZEROCOPY is not supported, falls back to regular sendmsg()
 */

#include "MT25033_Part_A_Common.h"
#include <sys/uio.h>
#include <signal.h>
#include <getopt.h>

#ifndef SO_ZEROCOPY
#define SO_ZEROCOPY 60
#endif

#ifndef MSG_ZEROCOPY
#define MSG_ZEROCOPY 0x4000000
#endif

/* Global flag for graceful shutdown */
static volatile int running = 1;
static int zerocopy_enabled = 0;

/* Signal handler for graceful termination */
void signal_handler(int signum) {
    (void)signum;
    running = 0;
}

/* Alarm handler to stop server after duration */
void alarm_handler(int signum) {
    (void)signum;
    running = 0;
}

/*
 * Thread function to handle a single client connection
 * Uses sendmsg() with MSG_ZEROCOPY for zero-copy transmission
 */
void* handle_client(void *arg) {
    ServerThreadArgs *args = (ServerThreadArgs*)arg;
    int client_fd = args->client_fd;
    size_t field_size = args->msg_size / NUM_FIELDS;
    int use_zerocopy = 0;

    /* Try to enable zero-copy on the socket */
    int optval = 1;
    if (setsockopt(client_fd, SOL_SOCKET, SO_ZEROCOPY, &optval, sizeof(optval)) == 0) {
        use_zerocopy = 1;
        zerocopy_enabled = 1;
        printf("[Thread %d] MSG_ZEROCOPY enabled\n", args->thread_id);
    } else {
        printf("[Thread %d] MSG_ZEROCOPY not available, using regular sendmsg()\n", args->thread_id);
    }

    /* Create message with heap-allocated fields */
    Message *msg = create_message(field_size);
    if (!msg) {
        close(client_fd);
        pthread_exit(NULL);
    }

    /*
     * Set up iovec array for scatter-gather I/O
     * With MSG_ZEROCOPY, these buffers are pinned and DMA'd directly
     */
    struct iovec iov[NUM_FIELDS];
    iov[0].iov_base = msg->field1; iov[0].iov_len = field_size;
    iov[1].iov_base = msg->field2; iov[1].iov_len = field_size;
    iov[2].iov_base = msg->field3; iov[2].iov_len = field_size;
    iov[3].iov_base = msg->field4; iov[3].iov_len = field_size;
    iov[4].iov_base = msg->field5; iov[4].iov_len = field_size;
    iov[5].iov_base = msg->field6; iov[5].iov_len = field_size;
    iov[6].iov_base = msg->field7; iov[6].iov_len = field_size;
    iov[7].iov_base = msg->field8; iov[7].iov_len = field_size;

    /* Set up msghdr structure */
    struct msghdr mh;
    memset(&mh, 0, sizeof(mh));
    mh.msg_iov = iov;
    mh.msg_iovlen = NUM_FIELDS;

    size_t total_msg_size = NUM_FIELDS * field_size;
    args->bytes_sent = 0;
    args->messages_sent = 0;

    double start_time = get_time_sec();
    double end_time = start_time + args->duration;

    printf("[Thread %d] Starting to send messages (size=%zu bytes, zerocopy=%s)\n",
           args->thread_id, total_msg_size, use_zerocopy ? "YES" : "NO");

    /* Send messages continuously until duration expires */
    while (running && get_time_sec() < end_time) {
        /*
         * ZERO-COPY sendmsg():
         * With MSG_ZEROCOPY flag, the kernel:
         * 1. Pins the user-space pages
         * 2. Sets up DMA from user buffer to NIC
         * 3. Returns immediately (async)
         *
         * If MSG_ZEROCOPY not supported, sends without the flag
         */
        ssize_t sent;
        if (use_zerocopy) {
            sent = sendmsg(client_fd, &mh, MSG_ZEROCOPY);
            /* If ZEROCOPY fails, fall back to regular send */
            if (sent < 0 && (errno == ENOBUFS || errno == EINVAL)) {
                sent = sendmsg(client_fd, &mh, 0);
            }
        } else {
            sent = sendmsg(client_fd, &mh, 0);
        }

        if (sent < 0) {
            if (errno == EPIPE || errno == ECONNRESET) {
                printf("[Thread %d] Client disconnected\n", args->thread_id);
                break;
            }
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                continue;
            }
            perror("sendmsg failed");
            break;
        }

        args->bytes_sent += sent;
        args->messages_sent++;
    }

    args->elapsed_time = get_time_sec() - start_time;

    printf("[Thread %d] Finished: sent %lu bytes (%lu messages) in %.2f seconds\n",
           args->thread_id, args->bytes_sent, args->messages_sent, args->elapsed_time);
    printf("[Thread %d] Throughput: %.4f Gbps\n",
           args->thread_id, calc_throughput_gbps(args->bytes_sent, args->elapsed_time));

    /* Cleanup */
    free_message(msg);
    close(client_fd);

    return NULL;
}

int main(int argc, char *argv[]) {
    int port = DEFAULT_PORT;
    size_t msg_size = DEFAULT_MSG_SIZE;
    int duration = DEFAULT_DURATION;
    int opt;

    /* Parse command line arguments */
    while ((opt = getopt(argc, argv, "p:s:d:h")) != -1) {
        switch (opt) {
            case 'p':
                port = atoi(optarg);
                break;
            case 's':
                msg_size = atoi(optarg);
                break;
            case 'd':
                duration = atoi(optarg);
                break;
            case 'h':
            default:
                print_usage(argv[0], 1);
                exit(EXIT_SUCCESS);
        }
    }

    /* Set up signal handler for graceful shutdown */
    signal(SIGINT, signal_handler);
    signal(SIGPIPE, SIG_IGN);
    signal(SIGALRM, alarm_handler);

    /* Set alarm to stop server after duration + buffer time */
    alarm(duration + 5);

    /* Create server socket */
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) {
        perror("socket creation failed");
        exit(EXIT_FAILURE);
    }

    /* Allow address reuse */
    int reuse = 1;
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse)) < 0) {
        perror("setsockopt SO_REUSEADDR failed");
        close(server_fd);
        exit(EXIT_FAILURE);
    }

    /* Set accept timeout so server doesn't block forever */
    struct timeval timeout;
    timeout.tv_sec = 2;
    timeout.tv_usec = 0;
    setsockopt(server_fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

    /* Bind to address */
    struct sockaddr_in server_addr;
    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY;
    server_addr.sin_port = htons(port);

    if (bind(server_fd, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
        perror("bind failed");
        close(server_fd);
        exit(EXIT_FAILURE);
    }

    /* Listen for connections */
    if (listen(server_fd, 10) < 0) {
        perror("listen failed");
        close(server_fd);
        exit(EXIT_FAILURE);
    }

    printf("=== Zero-Copy Server (MSG_ZEROCOPY) ===\n");
    printf("Listening on port %d\n", port);
    printf("Message size: %zu bytes, Duration: %d seconds\n", msg_size, duration);
    printf("Using MSG_ZEROCOPY for zero-copy transmission (if supported)\n");
    printf("Waiting for clients...\n\n");

    int thread_id = 0;
    pthread_t *threads = NULL;
    ServerThreadArgs *thread_args = NULL;
    int num_threads = 0;
    int max_threads = 100;

    threads = (pthread_t*)malloc(max_threads * sizeof(pthread_t));
    thread_args = (ServerThreadArgs*)malloc(max_threads * sizeof(ServerThreadArgs));

    /* Accept clients and spawn threads */
    while (running) {
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);

        int client_fd = accept(server_fd, (struct sockaddr*)&client_addr, &client_len);
        if (client_fd < 0) {
            if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) continue;
            perror("accept failed");
            continue;
        }

        printf("Client connected from %s:%d\n",
               inet_ntoa(client_addr.sin_addr), ntohs(client_addr.sin_port));

        if (num_threads >= max_threads) {
            printf("Maximum threads reached, rejecting client\n");
            close(client_fd);
            continue;
        }

        /* Set up thread arguments */
        thread_args[num_threads].client_fd = client_fd;
        thread_args[num_threads].thread_id = thread_id++;
        thread_args[num_threads].msg_size = msg_size;
        thread_args[num_threads].duration = duration;

        /* Create thread to handle client */
        if (pthread_create(&threads[num_threads], NULL, handle_client,
                          &thread_args[num_threads]) != 0) {
            perror("pthread_create failed");
            close(client_fd);
            continue;
        }

        num_threads++;
    }

    /* Wait for all threads to complete */
    printf("\nShutting down, waiting for threads...\n");
    for (int i = 0; i < num_threads; i++) {
        pthread_join(threads[i], NULL);
    }

    /* Calculate total metrics */
    unsigned long total_bytes = 0;
    unsigned long total_messages = 0;
    double max_time = 0;

    for (int i = 0; i < num_threads; i++) {
        total_bytes += thread_args[i].bytes_sent;
        total_messages += thread_args[i].messages_sent;
        if (thread_args[i].elapsed_time > max_time) {
            max_time = thread_args[i].elapsed_time;
        }
    }

    printf("\n=== Final Statistics ===\n");
    printf("Zero-Copy Enabled: %s\n", zerocopy_enabled ? "YES" : "NO (fallback to regular sendmsg)");
    printf("Total bytes sent: %lu\n", total_bytes);
    printf("Total messages sent: %lu\n", total_messages);
    printf("Aggregate throughput: %.4f Gbps\n", calc_throughput_gbps(total_bytes, max_time));

    /* Cleanup */
    free(threads);
    free(thread_args);
    close(server_fd);

    return 0;
}
