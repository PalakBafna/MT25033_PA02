/*
 * MT25033_Part_A3_Client.c
 * Zero-Copy Client Implementation
 * Roll Number: MT25033
 *
 * This client receives data from the zero-copy server.
 * Note: On the receive side, true zero-copy requires special mechanisms
 * like io_uring or splice(). For this implementation, we use recvmsg()
 * with pre-allocated buffers to minimize copies.
 *
 * The client measures throughput and latency for the zero-copy server.
 */

#include "MT25033_Part_A_Common.h"
#include <sys/uio.h>
#include <signal.h>
#include <getopt.h>

/* Global flag for graceful shutdown */
static volatile int running = 1;

/* Global metrics protected by mutex */
static pthread_mutex_t metrics_mutex = PTHREAD_MUTEX_INITIALIZER;
static Metrics global_metrics = {0};

/* Signal handler for graceful termination */
void signal_handler(int signum) {
    (void)signum;
    running = 0;
}

/*
 * Thread function for client connection
 * Receives data from zero-copy server
 */
void* client_thread(void *arg) {
    ClientThreadArgs *args = (ClientThreadArgs*)arg;
    size_t msg_size = args->msg_size;

    /* Create socket */
    int sock_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (sock_fd < 0) {
        perror("socket creation failed");
        pthread_exit(NULL);
    }

    /* Set up server address */
    struct sockaddr_in server_addr;
    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(args->server_port);

    if (inet_pton(AF_INET, args->server_ip, &server_addr.sin_addr) <= 0) {
        perror("Invalid address");
        close(sock_fd);
        pthread_exit(NULL);
    }

    /* Connect to server */
    if (connect(sock_fd, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
        perror("connect failed");
        close(sock_fd);
        pthread_exit(NULL);
    }

    printf("[Thread %d] Connected to server %s:%d\n",
           args->thread_id, args->server_ip, args->server_port);

    /*
     * Allocate page-aligned receive buffer for better performance
     * Page alignment can help with potential future zero-copy receives
     */
    char *recv_buffer;
    if (posix_memalign((void**)&recv_buffer, 4096, msg_size) != 0) {
        perror("Failed to allocate aligned receive buffer");
        close(sock_fd);
        pthread_exit(NULL);
    }

    /* Set up iovec for recvmsg */
    struct iovec iov;
    iov.iov_base = recv_buffer;
    iov.iov_len = msg_size;

    struct msghdr mh;
    memset(&mh, 0, sizeof(mh));
    mh.msg_iov = &iov;
    mh.msg_iovlen = 1;

    args->bytes_received = 0;
    args->messages_received = 0;
    args->total_latency = 0;

    double start_time = get_time_sec();
    double end_time = start_time + args->duration;

    printf("[Thread %d] Starting to receive messages\n", args->thread_id);

    /* Receive messages continuously until duration expires */
    while (running && get_time_sec() < end_time) {
        double msg_start = get_time_us();

        ssize_t received = recvmsg(sock_fd, &mh, 0);

        double msg_end = get_time_us();

        if (received < 0) {
            if (errno == EINTR) continue;
            perror("recvmsg failed");
            break;
        }

        if (received == 0) {
            printf("[Thread %d] Server closed connection\n", args->thread_id);
            break;
        }

        args->bytes_received += received;
        args->messages_received++;
        args->total_latency += (msg_end - msg_start);
    }

    args->elapsed_time = get_time_sec() - start_time;

    /* Calculate thread metrics */
    double throughput = calc_throughput_gbps(args->bytes_received, args->elapsed_time);
    double avg_latency = args->messages_received > 0 ?
                         args->total_latency / args->messages_received : 0;

    printf("[Thread %d] Finished: received %lu bytes (%lu messages) in %.2f seconds\n",
           args->thread_id, args->bytes_received, args->messages_received, args->elapsed_time);
    printf("[Thread %d] Throughput: %.4f Gbps, Avg Latency: %.2f µs\n",
           args->thread_id, throughput, avg_latency);

    /* Update global metrics */
    pthread_mutex_lock(&metrics_mutex);
    global_metrics.total_bytes += args->bytes_received;
    global_metrics.total_messages += args->messages_received;
    global_metrics.total_time = args->elapsed_time;
    global_metrics.avg_latency_us += avg_latency;
    pthread_mutex_unlock(&metrics_mutex);

    /* Cleanup */
    free(recv_buffer);
    close(sock_fd);

    return NULL;
}

int main(int argc, char *argv[]) {
    const char *server_ip = "127.0.0.1";
    int server_port = DEFAULT_PORT;
    size_t msg_size = DEFAULT_MSG_SIZE;
    int num_threads = DEFAULT_NUM_THREADS;
    int duration = DEFAULT_DURATION;
    int opt;

    /* Parse command line arguments */
    while ((opt = getopt(argc, argv, "i:p:s:t:d:h")) != -1) {
        switch (opt) {
            case 'i':
                server_ip = optarg;
                break;
            case 'p':
                server_port = atoi(optarg);
                break;
            case 's':
                msg_size = atoi(optarg);
                break;
            case 't':
                num_threads = atoi(optarg);
                break;
            case 'd':
                duration = atoi(optarg);
                break;
            case 'h':
            default:
                print_usage(argv[0], 0);
                exit(EXIT_SUCCESS);
        }
    }

    /* Set up signal handler */
    signal(SIGINT, signal_handler);

    printf("=== Zero-Copy Client ===\n");
    printf("Connecting to %s:%d\n", server_ip, server_port);
    printf("Message size: %zu bytes, Threads: %d, Duration: %d seconds\n",
           msg_size, num_threads, duration);
    printf("\n");

    /* Allocate thread resources */
    pthread_t *threads = (pthread_t*)malloc(num_threads * sizeof(pthread_t));
    ClientThreadArgs *thread_args = (ClientThreadArgs*)malloc(num_threads * sizeof(ClientThreadArgs));

    if (!threads || !thread_args) {
        perror("Failed to allocate thread resources");
        exit(EXIT_FAILURE);
    }

    /* Create client threads */
    for (int i = 0; i < num_threads; i++) {
        thread_args[i].thread_id = i;
        thread_args[i].server_ip = server_ip;
        thread_args[i].server_port = server_port;
        thread_args[i].msg_size = msg_size;
        thread_args[i].duration = duration;

        if (pthread_create(&threads[i], NULL, client_thread, &thread_args[i]) != 0) {
            perror("pthread_create failed");
            num_threads = i;
            break;
        }
    }

    /* Wait for all threads to complete */
    for (int i = 0; i < num_threads; i++) {
        pthread_join(threads[i], NULL);
    }

    /* Calculate final metrics */
    global_metrics.throughput_gbps = calc_throughput_gbps(global_metrics.total_bytes,
                                                          global_metrics.total_time);
    global_metrics.avg_latency_us /= num_threads;

    printf("\n=== Final Statistics ===\n");
    printf("Total bytes received: %lu\n", global_metrics.total_bytes);
    printf("Total messages received: %lu\n", global_metrics.total_messages);
    printf("Aggregate throughput: %.4f Gbps\n", global_metrics.throughput_gbps);
    printf("Average latency: %.2f µs\n", global_metrics.avg_latency_us);

    /* Output CSV-friendly line for scripting */
    printf("\nCSV: zero_copy,%zu,%d,%.4f,%.2f,%lu\n",
           msg_size, num_threads, global_metrics.throughput_gbps,
           global_metrics.avg_latency_us, global_metrics.total_bytes);

    /* Cleanup */
    free(threads);
    free(thread_args);

    return 0;
}
